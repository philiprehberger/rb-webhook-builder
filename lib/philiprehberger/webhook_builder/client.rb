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

      # Create a new webhook client.
      #
      # @param url [String] the webhook endpoint URL
      # @param secret [String] the HMAC-SHA256 signing secret
      # @param timeout [Integer] HTTP timeout in seconds (default: 30)
      # @param max_retries [Integer] maximum retry attempts on failure (default: 3)
      def initialize(url:, secret:, timeout: 30, max_retries: 3)
        @url = url
        @secret = secret
        @timeout = timeout
        @max_retries = max_retries
      end

      # Deliver a webhook event.
      #
      # @param event [String] the event type (e.g., "order.created")
      # @param payload [Hash] the event payload
      # @return [Delivery] the delivery result
      def deliver(event:, payload:)
        body = JSON.generate({ event: event, payload: payload, timestamp: Time.now.utc.iso8601 })
        signature = sign(body)

        attempts = 0
        start_time = monotonic_now
        last_response_code = nil
        last_response_body = nil
        last_error = nil

        loop do
          attempts += 1
          begin
            response = send_request(body, signature, event)
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

          sleep(backoff_delay(attempts))
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
      # @return [Net::HTTPResponse]
      def send_request(body, signature, event)
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
        request.body = body

        http.request(request)
      end

      # Calculate exponential backoff delay.
      #
      # @param attempt [Integer] the current attempt number
      # @return [Float] delay in seconds
      def backoff_delay(attempt)
        [2**(attempt - 1), 30].min
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
