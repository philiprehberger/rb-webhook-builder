# frozen_string_literal: true

module Philiprehberger
  module WebhookBuilder
    module Backoff
      # Exponential backoff: base * 2^attempt, capped at max_delay.
      class Exponential
        # @param base [Numeric] base delay in seconds (default: 1)
        # @param max_delay [Numeric] maximum delay in seconds (default: 30)
        # @param jitter [Boolean] whether to add random jitter (default: false)
        def initialize(base: 1, max_delay: 30, jitter: false)
          @base = base
          @max_delay = max_delay
          @jitter = jitter
        end

        # @param attempt [Integer] the current attempt number (1-based)
        # @return [Float] delay in seconds
        def call(attempt)
          delay = [@base * (2**(attempt - 1)), @max_delay].min.to_f
          delay *= rand if @jitter
          delay
        end
      end

      # Linear backoff: base * attempt, capped at max_delay.
      class Linear
        # @param base [Numeric] base delay in seconds (default: 1)
        # @param max_delay [Numeric] maximum delay in seconds (default: 30)
        def initialize(base: 1, max_delay: 30)
          @base = base
          @max_delay = max_delay
        end

        # @param attempt [Integer] the current attempt number (1-based)
        # @return [Float] delay in seconds
        def call(attempt)
          [@base * attempt, @max_delay].min.to_f
        end
      end

      # Fixed backoff: constant delay.
      class Fixed
        # @param delay [Numeric] delay in seconds (default: 1)
        def initialize(delay: 1)
          @delay = delay
        end

        # @param _attempt [Integer] ignored
        # @return [Float] delay in seconds
        def call(_attempt)
          @delay.to_f
        end
      end

      # Decorrelated jitter backoff (AWS-style): each delay is a random value
      # in `[base, [cap, prev * 3].min]`, which spreads retries to avoid
      # thundering-herd effects while still trending toward the cap.
      #
      # See: https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/
      class Decorrelated
        # @param base [Numeric] minimum delay in seconds (default: 1)
        # @param max_delay [Numeric] maximum delay in seconds (default: 30)
        def initialize(base: 1, max_delay: 30)
          @base = base.to_f
          @max_delay = max_delay.to_f
          @prev = @base
        end

        # @param _attempt [Integer] ignored (state is carried in @prev)
        # @return [Float] delay in seconds
        def call(_attempt)
          upper = [@max_delay, @prev * 3].min
          upper = @base if upper < @base
          @prev = @base + (rand * (upper - @base))
          @prev
        end
      end

      # Resolve a backoff option into a callable strategy.
      #
      # @param option [Symbol, Proc, nil] the backoff strategy
      # @return [#call] a callable backoff strategy
      def self.resolve(option)
        case option
        when :exponential, nil
          Exponential.new
        when :linear
          Linear.new
        when :fixed
          Fixed.new
        when :decorrelated
          Decorrelated.new
        when Proc
          option
        else
          raise ArgumentError,
                "Unknown backoff strategy: #{option.inspect}. " \
                'Use :exponential, :linear, :fixed, :decorrelated, or a Proc.'
        end
      end
    end
  end
end
