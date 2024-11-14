# Changelog

All notable changes to this gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.2] - 2026-04-15

### Changed
- Update homepage URI to portfolio hyphenated path

## [0.2.1] - 2026-03-31

### Changed
- Standardize README badges, support section, and license format

## [0.2.0] - 2026-03-29

### Added
- Batch delivery via `client.deliver_batch(events)` with configurable `concurrency:` option
- Retry backoff strategies: `:exponential` (default), `:linear`, `:fixed`, or custom Proc via `backoff:` option
- Backoff strategy classes in `Philiprehberger::WebhookBuilder::Backoff` module
- Header customization with per-delivery `headers:` parameter and client-level `default_headers:` option
- Per-delivery headers override default headers

## [0.1.1] - 2026-03-22

### Changed
- Expand test coverage

## [0.1.0] - 2026-03-22

### Added
- Initial release
- Webhook client with configurable URL, secret, timeout, and max retries
- HMAC-SHA256 payload signing
- Automatic retry with exponential backoff on failure
- Delivery tracking with success status, response code, attempts, and duration
