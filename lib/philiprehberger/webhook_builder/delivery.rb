# frozen_string_literal: true

module Philiprehberger
  module WebhookBuilder
    # Represents the result of a webhook delivery attempt.
    class Delivery
      # @return [Boolean] whether the delivery succeeded (2xx response)
      attr_reader :success

      # @return [Integer, nil] the HTTP response code
      attr_reader :response_code

      # @return [Integer] the number of delivery attempts made
      attr_reader :attempts

      # @return [Float] the total duration in seconds across all attempts
      attr_reader :duration

      # @return [String, nil] the response body
      attr_reader :response_body

      # @return [String, nil] the error message if delivery failed
      attr_reader :error

      # @param success [Boolean]
      # @param response_code [Integer, nil]
      # @param attempts [Integer]
      # @param duration [Float]
      # @param response_body [String, nil]
      # @param error [String, nil]
      def initialize(success:, response_code:, attempts:, duration:, response_body: nil, error: nil)
        @success = success
        @response_code = response_code
        @attempts = attempts
        @duration = duration
        @response_body = response_body
        @error = error
      end

      # Whether the delivery was successful.
      #
      # @return [Boolean]
      def success?
        @success
      end
    end
  end
end
