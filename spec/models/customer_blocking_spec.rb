# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customer, "blocking" do
  include ActiveSupport::Testing::TimeHelpers
  let(:company) { create(:company) }
  let(:manager) { create(:user, :manager, company: company) }
  let(:customer) { create(:customer, company: company) }

  before { Current.company = company }

  it "is not blocked by default" do
    expect(customer).not_to be_blocked
  end

  it "records who blocked them, when, and why" do
    freeze_time do
      customer.block!(by: manager, reason: "  Fake orders  ")
      customer.reload
      expect(customer).to be_blocked
      expect(customer.blocked_at).to eq(Time.current)
      expect(customer.blocked_by).to eq(manager)
      expect(customer.blocked_reason).to eq("Fake orders")
      expect(described_class.blocked).to eq([customer])
    end
  end

  it "clears everything on unblock" do
    customer.block!(by: manager, reason: "Fake orders")
    customer.unblock!
    customer.reload
    expect(customer).not_to be_blocked
    expect(customer.blocked_by).to be_nil
    expect(customer.blocked_reason).to be_nil
  end
end
