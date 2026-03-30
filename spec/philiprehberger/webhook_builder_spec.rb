# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Philiprehberger::WebhookBuilder do
  it 'has a version number' do
    expect(Philiprehberger::WebhookBuilder::VERSION).not_to be_nil
  end

  describe '.new' do
    it 'returns a Client instance' do
      client = described_class.new(url: 'https://example.com/webhook', secret: 'test-secret')
      expect(client).to be_a(Philiprehberger::WebhookBuilder::Client)
    end
  end
end

RSpec.describe Philiprehberger::WebhookBuilder::Client do
  subject(:client) do
    described_class.new(
      url: 'https://example.com/webhook',
      secret: 'test-secret',
      timeout: 5,
      max_retries: 2
    )
  end

  let(:success_response) do
    instance_double(Net::HTTPResponse, code: '200', body: '{"ok":true}')
  end

  let(:created_response) do
    instance_double(Net::HTTPResponse, code: '201', body: '{"created":true}')
  end

  let(:failure_response) do
    instance_double(Net::HTTPResponse, code: '500', body: 'Internal Server Error')
  end

  let(:not_found_response) do
    instance_double(Net::HTTPResponse, code: '404', body: 'Not Found')
  end

  let(:bad_gateway_response) do
    instance_double(Net::HTTPResponse, code: '502', body: 'Bad Gateway')
  end

  def stub_http(response)
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request).and_return(response)
    http
  end

  describe '#initialize' do
    it 'sets the url' do
      expect(client.url).to eq('https://example.com/webhook')
    end

    it 'sets the timeout' do
      expect(client.timeout).to eq(5)
    end

    it 'sets max_retries' do
      expect(client.max_retries).to eq(2)
    end

    it 'defaults timeout to 30' do
      c = described_class.new(url: 'https://example.com', secret: 's')
      expect(c.timeout).to eq(30)
    end

    it 'defaults max_retries to 3' do
      c = described_class.new(url: 'https://example.com', secret: 's')
      expect(c.max_retries).to eq(3)
    end

    it 'accepts zero max_retries' do
      c = described_class.new(url: 'https://example.com', secret: 's', max_retries: 0)
      expect(c.max_retries).to eq(0)
    end

    it 'accepts a custom timeout' do
      c = described_class.new(url: 'https://example.com', secret: 's', timeout: 60)
      expect(c.timeout).to eq(60)
    end

    it 'defaults concurrency to 4' do
      c = described_class.new(url: 'https://example.com', secret: 's')
      expect(c.concurrency).to eq(4)
    end

    it 'accepts a custom concurrency' do
      c = described_class.new(url: 'https://example.com', secret: 's', concurrency: 8)
      expect(c.concurrency).to eq(8)
    end

    it 'defaults default_headers to empty hash' do
      c = described_class.new(url: 'https://example.com', secret: 's')
      expect(c.default_headers).to eq({})
    end

    it 'accepts default_headers' do
      c = described_class.new(url: 'https://example.com', secret: 's', default_headers: { 'X-Tenant' => 'acme' })
      expect(c.default_headers).to eq({ 'X-Tenant' => 'acme' })
    end

    it 'freezes default_headers' do
      c = described_class.new(url: 'https://example.com', secret: 's', default_headers: { 'X-Foo' => 'bar' })
      expect(c.default_headers).to be_frozen
    end
  end

  describe '#deliver' do
    it 'returns a successful Delivery on 2xx response' do
      stub_http(success_response)

      delivery = client.deliver(event: 'order.created', payload: { id: 1 })

      expect(delivery).to be_success
      expect(delivery.response_code).to eq(200)
      expect(delivery.attempts).to eq(1)
      expect(delivery.duration).to be >= 0
    end

    it 'treats 201 as a successful response' do
      stub_http(created_response)

      delivery = client.deliver(event: 'order.created', payload: { id: 1 })

      expect(delivery).to be_success
      expect(delivery.response_code).to eq(201)
    end

    it 'retries on failure and returns failed Delivery' do
      stub_http(failure_response)
      allow(client).to receive(:sleep)

      delivery = client.deliver(event: 'order.created', payload: { id: 1 })

      expect(delivery).not_to be_success
      expect(delivery.response_code).to eq(500)
      expect(delivery.attempts).to eq(3) # 1 initial + 2 retries
      expect(delivery.error).to eq('HTTP 500')
    end

    it 'retries on network errors' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_raise(Errno::ECONNREFUSED)
      allow(client).to receive(:sleep)

      delivery = client.deliver(event: 'test.event', payload: {})

      expect(delivery).not_to be_success
      expect(delivery.attempts).to eq(3)
      expect(delivery.error).to match(/refused/i)
    end

    it 'includes HMAC signature in request headers' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)

      captured_request = nil
      allow(http).to receive(:request) do |req|
        captured_request = req
        success_response
      end

      client.deliver(event: 'test', payload: { key: 'value' })

      expect(captured_request['X-Webhook-Signature']).to match(/\A[0-9a-f]{64}\z/)
      expect(captured_request['X-Webhook-Event']).to eq('test')
      expect(captured_request['Content-Type']).to eq('application/json')
    end

    it 'includes User-Agent header' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)

      captured_request = nil
      allow(http).to receive(:request) do |req|
        captured_request = req
        success_response
      end

      client.deliver(event: 'test', payload: {})

      expect(captured_request['User-Agent']).to include('philiprehberger-webhook_builder/')
    end

    it 'sends JSON body containing event and payload' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)

      captured_body = nil
      allow(http).to receive(:request) do |req|
        captured_body = JSON.parse(req.body)
        success_response
      end

      client.deliver(event: 'order.created', payload: { id: 42 })

      expect(captured_body['event']).to eq('order.created')
      expect(captured_body['payload']).to eq({ 'id' => 42 })
      expect(captured_body).to have_key('timestamp')
    end

    it 'includes a timestamp in ISO 8601 format' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)

      captured_body = nil
      allow(http).to receive(:request) do |req|
        captured_body = JSON.parse(req.body)
        success_response
      end

      client.deliver(event: 'test', payload: {})

      expect { Time.iso8601(captured_body['timestamp']) }.not_to raise_error
    end

    it 'returns response_body on success' do
      stub_http(success_response)

      delivery = client.deliver(event: 'test', payload: {})

      expect(delivery.response_body).to eq('{"ok":true}')
    end

    it 'returns response_body on failure' do
      stub_http(failure_response)
      allow(client).to receive(:sleep)

      delivery = client.deliver(event: 'test', payload: {})

      expect(delivery.response_body).to eq('Internal Server Error')
    end

    it 'does not retry on success' do
      http = stub_http(success_response)

      client.deliver(event: 'test', payload: {})

      expect(http).to have_received(:request).once
    end

    it 'retries on 404 response' do
      stub_http(not_found_response)
      allow(client).to receive(:sleep)

      delivery = client.deliver(event: 'test', payload: {})

      expect(delivery).not_to be_success
      expect(delivery.response_code).to eq(404)
      expect(delivery.error).to eq('HTTP 404')
    end

    it 'succeeds on retry after initial failure' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      call_count = 0
      allow(http).to receive(:request) do
        call_count += 1
        call_count == 1 ? failure_response : success_response
      end
      allow(client).to receive(:sleep)

      delivery = client.deliver(event: 'test', payload: {})

      expect(delivery).to be_success
      expect(delivery.attempts).to eq(2)
    end

    it 'with zero max_retries does not retry' do
      zero_retry_client = described_class.new(
        url: 'https://example.com/webhook',
        secret: 'test-secret',
        max_retries: 0
      )
      stub_http(failure_response)

      delivery = zero_retry_client.deliver(event: 'test', payload: {})

      expect(delivery).not_to be_success
      expect(delivery.attempts).to eq(1)
    end

    it 'retries on timeout errors' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_raise(Net::OpenTimeout)
      allow(client).to receive(:sleep)

      delivery = client.deliver(event: 'test', payload: {})

      expect(delivery).not_to be_success
      expect(delivery.attempts).to eq(3)
    end

    context 'with custom per-delivery headers' do
      it 'includes per-delivery headers in the request' do
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)

        captured_request = nil
        allow(http).to receive(:request) do |req|
          captured_request = req
          success_response
        end

        client.deliver(event: 'test', payload: {}, headers: { 'X-Custom' => 'value' })

        expect(captured_request['X-Custom']).to eq('value')
      end
    end

    context 'with default headers' do
      subject(:client_with_defaults) do
        described_class.new(
          url: 'https://example.com/webhook',
          secret: 'test-secret',
          default_headers: { 'X-Tenant' => 'acme', 'X-Source' => 'default' }
        )
      end

      it 'includes default headers in every delivery' do
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)

        captured_request = nil
        allow(http).to receive(:request) do |req|
          captured_request = req
          success_response
        end

        client_with_defaults.deliver(event: 'test', payload: {})

        expect(captured_request['X-Tenant']).to eq('acme')
        expect(captured_request['X-Source']).to eq('default')
      end

      it 'allows per-delivery headers to override default headers' do
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)

        captured_request = nil
        allow(http).to receive(:request) do |req|
          captured_request = req
          success_response
        end

        client_with_defaults.deliver(event: 'test', payload: {}, headers: { 'X-Source' => 'override' })

        expect(captured_request['X-Tenant']).to eq('acme')
        expect(captured_request['X-Source']).to eq('override')
      end
    end
  end

  describe '#deliver_batch' do
    it 'delivers multiple events and returns results in order' do
      stub_http(success_response)

      events = [
        { event: 'order.created', payload: { id: 1 } },
        { event: 'order.updated', payload: { id: 2 } },
        { event: 'order.deleted', payload: { id: 3 } }
      ]

      results = client.deliver_batch(events)

      expect(results.length).to eq(3)
      results.each do |delivery|
        expect(delivery).to be_success
        expect(delivery.response_code).to eq(200)
      end
    end

    it 'returns an empty array for empty input' do
      results = client.deliver_batch([])
      expect(results).to eq([])
    end

    it 'preserves order even with concurrent delivery' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)

      call_count = 0
      mutex = Mutex.new
      allow(http).to receive(:request) do
        mutex.synchronize { call_count += 1 }
        success_response
      end

      events = (1..10).map { |i| { event: "event.#{i}", payload: { index: i } } }
      results = client.deliver_batch(events)

      expect(results.length).to eq(10)
      expect(results.all?(&:success?)).to be true
    end

    it 'handles mixed success and failure results' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)

      call_index = 0
      mutex = Mutex.new
      allow(http).to receive(:request) do
        idx = mutex.synchronize do
          call_index += 1
          call_index
        end
        idx.odd? ? success_response : failure_response
      end
      allow(client).to receive(:sleep)

      events = [
        { event: 'a', payload: {} },
        { event: 'b', payload: {} }
      ]

      results = client.deliver_batch(events)
      expect(results.length).to eq(2)
    end

    it 'respects concurrency limit' do
      concurrent_count = 0
      max_concurrent = 0
      mutex = Mutex.new

      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request) do
        mutex.synchronize do
          concurrent_count += 1
          max_concurrent = [max_concurrent, concurrent_count].max
        end
        sleep(0.01)
        mutex.synchronize { concurrent_count -= 1 }
        success_response
      end

      limited_client = described_class.new(
        url: 'https://example.com/webhook',
        secret: 'test-secret',
        concurrency: 2,
        max_retries: 0
      )

      events = (1..6).map { |i| { event: "event.#{i}", payload: {} } }
      limited_client.deliver_batch(events)

      expect(max_concurrent).to be <= 2
    end

    it 'passes per-event headers to each delivery' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)

      captured_requests = []
      mutex = Mutex.new
      allow(http).to receive(:request) do |req|
        mutex.synchronize { captured_requests << req }
        success_response
      end

      events = [
        { event: 'a', payload: {}, headers: { 'X-Custom' => 'one' } },
        { event: 'b', payload: {}, headers: { 'X-Custom' => 'two' } }
      ]

      client.deliver_batch(events)

      custom_values = captured_requests.map { |r| r['X-Custom'] }.sort
      expect(custom_values).to eq(%w[one two])
    end
  end
end

RSpec.describe Philiprehberger::WebhookBuilder::Delivery do
  describe '#success?' do
    it 'returns true for successful deliveries' do
      delivery = described_class.new(success: true, response_code: 200, attempts: 1, duration: 0.5)
      expect(delivery).to be_success
    end

    it 'returns false for failed deliveries' do
      delivery = described_class.new(success: false, response_code: 500, attempts: 3, duration: 5.0, error: 'HTTP 500')
      expect(delivery).not_to be_success
    end
  end

  describe 'attributes' do
    it 'exposes all delivery attributes' do
      delivery = described_class.new(
        success: true,
        response_code: 201,
        attempts: 2,
        duration: 1.5,
        response_body: '{"ok":true}',
        error: nil
      )

      expect(delivery.response_code).to eq(201)
      expect(delivery.attempts).to eq(2)
      expect(delivery.duration).to eq(1.5)
      expect(delivery.response_body).to eq('{"ok":true}')
      expect(delivery.error).to be_nil
    end

    it 'defaults response_body to nil' do
      delivery = described_class.new(success: true, response_code: 200, attempts: 1, duration: 0.1)
      expect(delivery.response_body).to be_nil
    end

    it 'defaults error to nil' do
      delivery = described_class.new(success: true, response_code: 200, attempts: 1, duration: 0.1)
      expect(delivery.error).to be_nil
    end

    it 'stores error message for failed deliveries' do
      delivery = described_class.new(
        success: false,
        response_code: nil,
        attempts: 3,
        duration: 10.0,
        error: 'Connection refused'
      )

      expect(delivery.error).to eq('Connection refused')
      expect(delivery.response_code).to be_nil
    end
  end
end

RSpec.describe Philiprehberger::WebhookBuilder::Backoff do
  describe '.resolve' do
    it 'returns Exponential for :exponential' do
      strategy = described_class.resolve(:exponential)
      expect(strategy).to be_a(Philiprehberger::WebhookBuilder::Backoff::Exponential)
    end

    it 'returns Exponential for nil' do
      strategy = described_class.resolve(nil)
      expect(strategy).to be_a(Philiprehberger::WebhookBuilder::Backoff::Exponential)
    end

    it 'returns Linear for :linear' do
      strategy = described_class.resolve(:linear)
      expect(strategy).to be_a(Philiprehberger::WebhookBuilder::Backoff::Linear)
    end

    it 'returns Fixed for :fixed' do
      strategy = described_class.resolve(:fixed)
      expect(strategy).to be_a(Philiprehberger::WebhookBuilder::Backoff::Fixed)
    end

    it 'returns the Proc for a custom Proc' do
      custom = ->(attempt) { attempt * 0.5 }
      strategy = described_class.resolve(custom)
      expect(strategy).to eq(custom)
    end

    it 'raises ArgumentError for unknown strategy' do
      expect { described_class.resolve(:unknown) }.to raise_error(ArgumentError, /Unknown backoff strategy/)
    end
  end

  describe Philiprehberger::WebhookBuilder::Backoff::Exponential do
    subject(:strategy) { described_class.new }

    it 'doubles delay with each attempt' do
      expect(strategy.call(1)).to eq(1.0)
      expect(strategy.call(2)).to eq(2.0)
      expect(strategy.call(3)).to eq(4.0)
      expect(strategy.call(4)).to eq(8.0)
    end

    it 'caps at max_delay' do
      expect(strategy.call(10)).to eq(30.0)
    end

    it 'accepts custom base' do
      s = described_class.new(base: 2)
      expect(s.call(1)).to eq(2.0)
      expect(s.call(2)).to eq(4.0)
    end

    it 'accepts custom max_delay' do
      s = described_class.new(max_delay: 10)
      expect(s.call(5)).to eq(10.0)
    end

    it 'applies jitter when enabled' do
      s = described_class.new(jitter: true)
      allow(s).to receive(:rand).and_return(0.5)

      # With jitter, delay = base * 2^(attempt-1) * rand
      delay = s.call(3)
      expect(delay).to eq(2.0) # 4.0 * 0.5
    end
  end

  describe Philiprehberger::WebhookBuilder::Backoff::Linear do
    subject(:strategy) { described_class.new }

    it 'increases linearly with each attempt' do
      expect(strategy.call(1)).to eq(1.0)
      expect(strategy.call(2)).to eq(2.0)
      expect(strategy.call(3)).to eq(3.0)
    end

    it 'caps at max_delay' do
      expect(strategy.call(100)).to eq(30.0)
    end

    it 'accepts custom base' do
      s = described_class.new(base: 3)
      expect(s.call(2)).to eq(6.0)
    end

    it 'accepts custom max_delay' do
      s = described_class.new(max_delay: 5)
      expect(s.call(10)).to eq(5.0)
    end
  end

  describe Philiprehberger::WebhookBuilder::Backoff::Fixed do
    subject(:strategy) { described_class.new }

    it 'returns constant delay regardless of attempt' do
      expect(strategy.call(1)).to eq(1.0)
      expect(strategy.call(5)).to eq(1.0)
      expect(strategy.call(100)).to eq(1.0)
    end

    it 'accepts custom delay' do
      s = described_class.new(delay: 5)
      expect(s.call(1)).to eq(5.0)
      expect(s.call(10)).to eq(5.0)
    end
  end
end

RSpec.describe 'Backoff integration with Client' do
  let(:success_response) do
    instance_double(Net::HTTPResponse, code: '200', body: '{"ok":true}')
  end

  let(:failure_response) do
    instance_double(Net::HTTPResponse, code: '500', body: 'error')
  end

  def stub_http(response)
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request).and_return(response)
    http
  end

  it 'uses linear backoff when configured' do
    client = Philiprehberger::WebhookBuilder::Client.new(
      url: 'https://example.com/webhook',
      secret: 'test-secret',
      max_retries: 2,
      backoff: :linear
    )
    stub_http(failure_response)

    delays = []
    allow(client).to receive(:sleep) { |d| delays << d }

    client.deliver(event: 'test', payload: {})

    expect(delays).to eq([1.0, 2.0])
  end

  it 'uses fixed backoff when configured' do
    client = Philiprehberger::WebhookBuilder::Client.new(
      url: 'https://example.com/webhook',
      secret: 'test-secret',
      max_retries: 2,
      backoff: :fixed
    )
    stub_http(failure_response)

    delays = []
    allow(client).to receive(:sleep) { |d| delays << d }

    client.deliver(event: 'test', payload: {})

    expect(delays).to eq([1.0, 1.0])
  end

  it 'uses custom Proc backoff when configured' do
    client = Philiprehberger::WebhookBuilder::Client.new(
      url: 'https://example.com/webhook',
      secret: 'test-secret',
      max_retries: 2,
      backoff: ->(attempt) { attempt * 0.1 }
    )
    stub_http(failure_response)

    delays = []
    allow(client).to receive(:sleep) { |d| delays << d }

    client.deliver(event: 'test', payload: {})

    expect(delays).to eq([0.1, 0.2])
  end

  it 'uses exponential backoff by default' do
    client = Philiprehberger::WebhookBuilder::Client.new(
      url: 'https://example.com/webhook',
      secret: 'test-secret',
      max_retries: 3
    )
    stub_http(failure_response)

    delays = []
    allow(client).to receive(:sleep) { |d| delays << d }

    client.deliver(event: 'test', payload: {})

    expect(delays).to eq([1.0, 2.0, 4.0])
  end
end
