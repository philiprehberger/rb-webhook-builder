# frozen_string_literal: true

module Philiprehberger
  module WebhookBuilder
    class Error < StandardError; end

    # Convenience method to create a new webhook client.
    #
    # @param options [Hash] options passed to {Client#initialize}
    # @return [Client] a new webhook client
    # @see Client#initialize
    def self.new(**options)
      Client.new(**options)
    end
  end
end

require_relative 'webhook_builder/version'
require_relative 'webhook_builder/delivery'
require_relative 'webhook_builder/backoff'
require_relative 'webhook_builder/client'
