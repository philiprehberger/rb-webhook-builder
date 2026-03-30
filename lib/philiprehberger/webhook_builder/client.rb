# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'openssl'
require 'time'

module Philiprehberger
  module WebhookBuilder
    # Webhook delivery client with HMAC signing, retry, and tracking.
    class Client
      # @return [String] the webhook endpoint URL
      attr_reader :url

      # @return [Integer] the HTTP timeout in seconds
      attr_reader :timeout

      # @return [Integer] the maximum number of delivery attempts
      attr_reader :max_retries

      # @return [Integer] the maximum number of concurrent batch deliveries
      attr_reader :concurrency

      # @return [Hash] default headers included in every delivery
      attr_reader :default_headers

      # Create a new webhook client.
      #
      # @param url [String] the webhook endpoint URL
      # @param secret [String] the HMAC-SHA256 signing secret
      # @param timeout [Integer] HTTP timeout in seconds (default: 30)
      # @param max_retries [Integer] maximum retry attempts on failure (default: 3)
      # @param backoff [Symbol, Proc] backoff strategy — :exponential (default), :linear, :fixed, or a Proc
      # @param concurrency [Integer] maximum concurrent threads for batch delivery (default: 4)
      # @param default_headers [Hash] headers to include in every delivery
      def initialize(url:, secret:, timeout: 30, max_retries: 3, backoff: :exponential, concurrency: 4,
                     default_headers: {})
        @url = url
        @secret = secret
        @timeout = timeout
        @max_retries = max_retries
        @backoff_strategy = Backoff.resolve(backoff)
        @concurrency = concurrency
        @default_headers = default_headers.dup.freeze
      end

      # Deliver a webhook event.
      #
      # @param event [String] the event type (e.g., "order.created")
      # @param payload [Hash] the event payload
      # @param headers [Hash] per-delivery headers (override default_headers)
      # @return [Delivery] the delivery result
      def deliver(event:, payload:, headers: {})
        body = JSON.generate({ event: event, payload: payload, timestamp: Time.now.utc.iso8601 })
        signature = sign(body)
        merged_headers = @default_headers.merge(headers)

        attempts = 0
        start_time = monotonic_now
        last_response_code = nil
        last_response_body = nil
        last_error = nil

        loop do
          attempts += 1
          begin
            response = send_request(body, signature, event, merged_headers)
            last_response_code = response.code.to_i
            last_response_body = response.body

            if last_response_code >= 200 && last_response_code < 300
              return Delivery.new(
                success: true,
                response_code: last_response_code,
                attempts: attempts,
                duration: monotonic_now - start_time,
                response_body: last_response_body
              )
            end

            last_error = "HTTP #{last_response_code}"
          rescue StandardError => e
            last_error = e.message
          end

          break if attempts > @max_retries

          sleep(@backoff_strategy.call(attempts))
        end

        Delivery.new(
          success: false,
          response_code: last_response_code,
          attempts: attempts,
          duration: monotonic_now - start_time,
          response_body: last_response_body,
          error: last_error
        )
      end

      # Deliver multiple webhook events concurrently.
      #
      # @param events [Array<Hash>] array of { event:, payload: } hashes, optionally with headers:
      # @return [Array<Delivery>] delivery results in the same order as input
      def deliver_batch(events)
        results = Array.new(events.length)
        mutex = Mutex.new
        queue = Queue.new

        events.each_with_index do |item, index|
          queue << [item, index]
        end

        threads = Array.new([@concurrency, events.length].min) do
          Thread.new do
            loop do
              pair = begin
                queue.pop(true)
              rescue ThreadError
                nil
              end
              break unless pair

              item, index = pair
              delivery = deliver(
                event: item[:event],
                payload: item[:payload],
                headers: item.fetch(:headers, {})
              )
              mutex.synchronize { results[index] = delivery }
            end
          end
        end

        threads.each(&:join)
        results
      end

      private

      # Sign the request body with HMAC-SHA256.
      #
      # @param body [String] the JSON body
      # @return [String] the hex-encoded HMAC signature
      def sign(body)
        OpenSSL::HMAC.hexdigest('SHA256', @secret, body)
      end

      # Send the HTTP POST request.
      #
      # @param body [String] the JSON body
      # @param signature [String] the HMAC signature
      # @param event [String] the event type
      # @param extra_headers [Hash] additional headers to include
      # @return [Net::HTTPResponse]
      def send_request(body, signature, event, extra_headers = {})
        uri = URI.parse(@url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = @timeout
        http.read_timeout = @timeout

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        request['X-Webhook-Signature'] = signature
        request['X-Webhook-Event'] = event
        request['User-Agent'] = "philiprehberger-webhook_builder/#{VERSION}"

        extra_headers.each { |key, value| request[key] = value }

        request.body = body

        http.request(request)
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
