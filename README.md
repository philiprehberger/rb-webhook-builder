# philiprehberger-webhook_builder

[![Tests](https://github.com/philiprehberger/rb-webhook-builder/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-webhook-builder/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/philiprehberger-webhook_builder.svg)](https://rubygems.org/gems/philiprehberger-webhook_builder)
[![License](https://img.shields.io/github/license/philiprehberger/rb-webhook-builder)](LICENSE)
[![Sponsor](https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ec6cb9)](https://github.com/sponsors/philiprehberger)

Webhook delivery client with HMAC signing, retry, and tracking

## Requirements

- Ruby >= 3.1

## Installation

Add to your Gemfile:

```ruby
gem "philiprehberger-webhook_builder"
```

Or install directly:

```bash
gem install philiprehberger-webhook_builder
```

## Usage

```ruby
require "philiprehberger/webhook_builder"

client = Philiprehberger::WebhookBuilder.new(
  url: "https://example.com/webhooks",
  secret: "your-signing-secret"
)

delivery = client.deliver(event: "order.created", payload: { id: 123, total: 49.99 })
delivery.success?      # => true
delivery.response_code # => 200
```

### Custom Options

```ruby
client = Philiprehberger::WebhookBuilder.new(
  url: "https://api.example.com/hooks",
  secret: "hmac-secret",
  timeout: 10,
  max_retries: 5
)
```

### Delivery Tracking

```ruby
delivery = client.deliver(event: "user.updated", payload: { id: 42 })

delivery.success?       # => true/false
delivery.response_code  # => 200
delivery.attempts       # => 1
delivery.duration       # => 0.342 (seconds)
delivery.response_body  # => '{"ok":true}'
delivery.error          # => nil or error message
```

### HMAC Signing

Every request includes an `X-Webhook-Signature` header with an HMAC-SHA256 hex digest of the JSON body, signed with the configured secret. The `X-Webhook-Event` header contains the event type.

## API

### `Client`

| Method | Description |
|--------|-------------|
| `.new(url:, secret:, timeout:, max_retries:)` | Create a webhook client (timeout defaults to 30s, retries to 3) |
| `#deliver(event:, payload:)` | Deliver a webhook event and return a Delivery |

### `Delivery`

| Method | Description |
|--------|-------------|
| `#success?` | Whether the delivery succeeded (2xx response) |
| `#response_code` | The HTTP response code |
| `#attempts` | Number of delivery attempts made |
| `#duration` | Total duration in seconds across all attempts |
| `#response_body` | The response body string |
| `#error` | Error message if delivery failed |

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

MIT
