# frozen_string_literal: true

require "rails_helper"

RSpec.describe Printing::Drivers::Network do
  describe ".friendly_error_message" do
    it "maps connect timeout to a helpful message" do
      message = described_class.send(
        :friendly_error_message,
        Errno::ETIMEDOUT.new,
        host: "192.168.1.50",
        port: 9100
      )

      expect(message).to include("192.168.1.50")
      expect(message).to include("9100")
      expect(message).to include("nc -zv")
    end
  end

  describe ".check_connection" do
    it "reports failure when the printer is unreachable" do
      allow(described_class).to receive(:connect!).and_raise(Errno::ETIMEDOUT)

      result = described_class.check_connection(host: "192.168.1.50", port: 9100)

      expect(result[:ok]).to be(false)
      expect(result[:error]).to be_present
    end

    it "reports success with latency when connect succeeds" do
      socket = instance_double(Socket, close: true)
      allow(described_class).to receive(:connect!).and_return(socket)

      result = described_class.check_connection(host: "192.168.1.50", port: 9100)

      expect(result[:ok]).to be(true)
      expect(result[:latency_ms]).to be_a(Integer)
    end
  end
end
