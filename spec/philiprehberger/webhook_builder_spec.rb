# frozen_string_literal: true

require "spec_helper"

RSpec.describe Philiprehberger::WebhookBuilder do
  it "has a version number" do
    expect(Philiprehberger::WebhookBuilder::VERSION).not_to be_nil
  end

  describe ".new" do
    it "returns a Client instance" do
      client = described_class.new(url: "https://example.com/webhook", secret: "test-secret")
      expect(client).to be_a(Philiprehberger::WebhookBuilder::Client)
    end
  end
end

RSpec.describe Philiprehberger::WebhookBuilder::Client do
  subject(:client) do
    described_class.new(
      url: "https://example.com/webhook",
      secret: "test-secret",
      timeout: 5,
      max_retries: 2
    )
  end

  describe "#initialize" do
    it "sets the url" do
      expect(client.url).to eq("https://example.com/webhook")
    end

    it "sets the timeout" do
      expect(client.timeout).to eq(5)
    end

    it "sets max_retries" do
      expect(client.max_retries).to eq(2)
    end

    it "defaults timeout to 30" do
      c = described_class.new(url: "https://example.com", secret: "s")
      expect(c.timeout).to eq(30)
    end

    it "defaults max_retries to 3" do
      c = described_class.new(url: "https://example.com", secret: "s")
      expect(c.max_retries).to eq(3)
    end
  end

  describe "#deliver" do
    let(:success_response) do
      instance_double(Net::HTTPResponse, code: "200", body: '{"ok":true}')
    end

    let(:failure_response) do
      instance_double(Net::HTTPResponse, code: "500", body: "Internal Server Error")
    end

    it "returns a successful Delivery on 2xx response" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(success_response)

      delivery = client.deliver(event: "order.created", payload: { id: 1 })

      expect(delivery).to be_success
      expect(delivery.response_code).to eq(200)
      expect(delivery.attempts).to eq(1)
      expect(delivery.duration).to be >= 0
    end

    it "retries on failure and returns failed Delivery" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(failure_response)
      allow(client).to receive(:sleep)

      delivery = client.deliver(event: "order.created", payload: { id: 1 })

      expect(delivery).not_to be_success
      expect(delivery.response_code).to eq(500)
      expect(delivery.attempts).to eq(3) # 1 initial + 2 retries
      expect(delivery.error).to eq("HTTP 500")
    end

    it "retries on network errors" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_raise(Errno::ECONNREFUSED)
      allow(client).to receive(:sleep)

      delivery = client.deliver(event: "test.event", payload: {})

      expect(delivery).not_to be_success
      expect(delivery.attempts).to eq(3)
      expect(delivery.error).to include("Connection refused")
    end

    it "includes HMAC signature in request headers" do
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

      client.deliver(event: "test", payload: { key: "value" })

      expect(captured_request["X-Webhook-Signature"]).to match(/\A[0-9a-f]{64}\z/)
      expect(captured_request["X-Webhook-Event"]).to eq("test")
      expect(captured_request["Content-Type"]).to eq("application/json")
    end
  end
end

RSpec.describe Philiprehberger::WebhookBuilder::Delivery do
  describe "#success?" do
    it "returns true for successful deliveries" do
      delivery = described_class.new(success: true, response_code: 200, attempts: 1, duration: 0.5)
      expect(delivery).to be_success
    end

    it "returns false for failed deliveries" do
      delivery = described_class.new(success: false, response_code: 500, attempts: 3, duration: 5.0, error: "HTTP 500")
      expect(delivery).not_to be_success
    end
  end

  describe "attributes" do
    it "exposes all delivery attributes" do
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
  end
end
