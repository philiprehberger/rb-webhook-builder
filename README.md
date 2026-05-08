# philiprehberger-webhook_builder

[![Tests](https://github.com/philiprehberger/rb-webhook-builder/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-webhook-builder/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/philiprehberger-webhook_builder.svg)](https://rubygems.org/gems/philiprehberger-webhook_builder)
[![Last updated](https://img.shields.io/github/last-commit/philiprehberger/rb-webhook-builder)](https://github.com/philiprehberger/rb-webhook-builder/commits/main)

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

### Batch Delivery

```ruby
require "philiprehberger/webhook_builder"

client = Philiprehberger::WebhookBuilder.new(
  url: "https://example.com/webhooks",
  secret: "your-signing-secret",
  concurrency: 8
)

events = [
  { event: "order.created", payload: { id: 1 } },
  { event: "order.updated", payload: { id: 2 } },
  { event: "order.deleted", payload: { id: 3 } }
]

results = client.deliver_batch(events)
results.each { |d| puts "#{d.response_code}: #{d.success?}" }
```

### Backoff Strategies

```ruby
require "philiprehberger/webhook_builder"

# Exponential backoff (default): 1s, 2s, 4s, 8s, ...
client = Philiprehberger::WebhookBuilder.new(
  url: "https://example.com/webhooks",
  secret: "secret",
  backoff: :exponential
)

# Linear backoff: 1s, 2s, 3s, 4s, ...
client = Philiprehberger::WebhookBuilder.new(
  url: "https://example.com/webhooks",
  secret: "secret",
  backoff: :linear
)

# Fixed backoff: 1s, 1s, 1s, ...
client = Philiprehberger::WebhookBuilder.new(
  url: "https://example.com/webhooks",
  secret: "secret",
  backoff: :fixed
)

# Decorrelated jitter (AWS-style): randomized within [base, min(cap, prev*3)]
client = Philiprehberger::WebhookBuilder.new(
  url: "https://example.com/webhooks",
  secret: "secret",
  backoff: :decorrelated
)

# Custom Proc backoff
client = Philiprehberger::WebhookBuilder.new(
  url: "https://example.com/webhooks",
  secret: "secret",
  backoff: ->(attempt) { attempt * 0.5 }
)
```

### Header Customization

```ruby
require "philiprehberger/webhook_builder"

# Default headers on all deliveries
client = Philiprehberger::WebhookBuilder.new(
  url: "https://example.com/webhooks",
  secret: "secret",
  default_headers: { "X-Tenant" => "acme" }
)

# Per-delivery headers (override defaults)
client.deliver(
  event: "order.created",
  payload: { id: 1 },
  headers: { "X-Priority" => "high" }
)
```

### Verifying signatures

On the receiving side, use the same secret to verify the signature sent in the
`X-Webhook-Signature` header. The comparison is constant-time and will never
raise on malformed input.

```ruby
require "philiprehberger/webhook_builder"

secret = "shared-signing-secret"
sender = Philiprehberger::WebhookBuilder.new(url: "https://example.com/webhooks", secret: secret)
receiver = Philiprehberger::WebhookBuilder.new(url: "https://example.com/webhooks", secret: secret)

body = '{"event":"order.created","payload":{"id":1}}'
signature = OpenSSL::HMAC.hexdigest("SHA256", secret, body)

receiver.verify_signature(body: body, signature: signature) # => true
receiver.verify_signature(body: body, signature: "tampered") # => false
```

You can also compute the signature the client would send for a body without
performing a delivery — useful for preparing payloads offline or mirroring
`verify_signature`:

```ruby
require "philiprehberger/webhook_builder"

client = Philiprehberger::WebhookBuilder.new(
  url: "https://example.com/webhooks",
  secret: "shared-signing-secret"
)

body = '{"event":"order.created","payload":{"id":1}}'
signature = client.signature_for(body: body)

client.verify_signature(body: body, signature: signature) # => true
```

### Delivery Tracking

```ruby
require "philiprehberger/webhook_builder"

client = Philiprehberger::WebhookBuilder.new(
  url: "https://example.com/webhooks",
  secret: "secret"
)

delivery = client.deliver(event: "user.updated", payload: { id: 42 })

delivery.success?       # => true/false
delivery.response_code  # => 200
delivery.attempts       # => 1
delivery.duration       # => 0.342 (seconds)
delivery.response_body  # => '{"ok":true}'
delivery.error          # => nil or error message
```

## API

### `Client`

| Method | Description |
|--------|-------------|
| `.new(url:, secret:, timeout:, max_retries:, backoff:, concurrency:, default_headers:)` | Create a webhook client |
| `#deliver(event:, payload:, headers:)` | Deliver a webhook event and return a Delivery |
| `#deliver_batch(events)` | Deliver multiple events concurrently and return an array of Delivery results |
| `#verify_signature(body:, signature:)` | Constant-time HMAC-SHA256 verification of an incoming signature; returns `true`/`false` and never raises |
| `#signature_for(body:)` | Compute the HMAC-SHA256 signature for a body without sending |

### `Delivery`

| Method | Description |
|--------|-------------|
| `#success?` | Whether the delivery succeeded (2xx response) |
| `#response_code` | The HTTP response code |
| `#attempts` | Number of delivery attempts made |
| `#duration` | Total duration in seconds across all attempts |
| `#response_body` | The response body string |
| `#error` | Error message if delivery failed |

### `Backoff::Exponential`

| Method | Description |
|--------|-------------|
| `.new(base:, max_delay:, jitter:)` | Create exponential strategy (defaults: base=1, max_delay=30, jitter=false) |
| `#call(attempt)` | Calculate delay for given attempt |

### `Backoff::Linear`

| Method | Description |
|--------|-------------|
| `.new(base:, max_delay:)` | Create linear strategy (defaults: base=1, max_delay=30) |
| `#call(attempt)` | Calculate delay for given attempt |

### `Backoff::Fixed`

| Method | Description |
|--------|-------------|
| `.new(delay:)` | Create fixed strategy (default: delay=1) |
| `#call(attempt)` | Returns constant delay |

### `Backoff::Decorrelated`

| Method | Description |
|--------|-------------|
| `.new(base:, max_delay:)` | Create decorrelated jitter strategy (defaults: base=1, max_delay=30) |
| `#call(attempt)` | Returns randomized delay in `[base, min(max_delay, prev * 3)]` |

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## Support

If you find this project useful:

⭐ [Star the repo](https://github.com/philiprehberger/rb-webhook-builder)

🐛 [Report issues](https://github.com/philiprehberger/rb-webhook-builder/issues?q=is%3Aissue+is%3Aopen+label%3Abug)

💡 [Suggest features](https://github.com/philiprehberger/rb-webhook-builder/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement)

❤️ [Sponsor development](https://github.com/sponsors/philiprehberger)

🌐 [All Open Source Projects](https://philiprehberger.com/open-source-packages)

💻 [GitHub Profile](https://github.com/philiprehberger)

🔗 [LinkedIn Profile](https://www.linkedin.com/in/philiprehberger)

## License

[MIT](LICENSE)
