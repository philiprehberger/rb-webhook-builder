# frozen_string_literal: true

require_relative 'lib/philiprehberger/webhook_builder/version'

Gem::Specification.new do |spec|
  spec.name = 'philiprehberger-webhook_builder'
  spec.version = Philiprehberger::WebhookBuilder::VERSION
  spec.authors = ['Philip Rehberger']
  spec.email = ['me@philiprehberger.com']

  spec.summary = 'Webhook delivery client with HMAC signing, retry, and tracking'
  spec.description = 'A webhook delivery client that signs payloads with HMAC-SHA256, ' \
                     'retries failed deliveries with configurable backoff strategies, ' \
                     'supports batch delivery, custom headers, and tracks delivery status ' \
                     'including response codes, attempts, and duration.'
  spec.homepage = 'https://github.com/philiprehberger/rb-webhook-builder'
  spec.license = 'MIT'

  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*.rb', 'LICENSE', 'README.md', 'CHANGELOG.md']
  spec.require_paths = ['lib']
end
