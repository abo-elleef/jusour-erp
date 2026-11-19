# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::Levels do
  let(:company) { create(:company) }

  before { Current.company = company }

  it "uses the built-in default for each kind" do
    expect(described_class.for("customer_invoice_payment_pending")).to eq("alert")
    expect(described_class.for("price_change")).to eq("popup")
    expect(described_class.for("low_stock")).to eq("quiet")
  end

  it "falls back to popup for an unknown or missing kind" do
    expect(described_class.for("something_new")).to eq("popup")
    expect(described_class.for(nil)).to eq("popup")
  end

  it "lets the company override a kind, ignoring invalid levels" do
    CompanySetting.create!(company: company, notification_levels: { "low_stock" => "alert", "price_change" => "loud" })

    expect(described_class.for("low_stock")).to eq("alert")
    expect(described_class.for("price_change")).to eq("popup")
    expect(described_class.all).to include("low_stock" => "alert", "cash_variance" => "alert")
  end

  it "keeps only known kinds and valid levels that differ from the default" do
    stored = described_class.sanitize(
      "low_stock" => "popup", "cash_variance" => "alert", "bogus" => "quiet", "price_change" => "loud"
    )

    expect(stored).to eq("low_stock" => "popup")
  end

  # A new kind of notification still pops up (unknown keys fall back to popup),
  # but it only appears on the Settings page once it is in DEFAULTS. This scans
  # the code for every literal message_key so a new one can't be forgotten.
  describe "every kind the app sends" do
    let(:sent_keys) do
      Dir[Rails.root.join("{app,lib}/**/*.rb")].flat_map do |file|
        File.read(file).scan(/["']?message_key["']?\s*(?::|=>)\s*["']([a-z0-9_]+)["']/).flatten
      end.uniq.sort
    end

    it "finds the kinds (guards the scan itself)" do
      expect(sent_keys).to include("low_stock", "customer_invoice_payment_pending")
    end

    it "has a default level, so the owner can set it on the Settings page" do
      missing = sent_keys - described_class::KEYS
      expect(missing).to be_empty,
                         "Add these to Notifications::Levels::DEFAULTS with a default level: #{missing.join(", ")}"
    end

    it "has a label in every language, for Settings and the bell list" do
      missing = I18n.available_locales.flat_map do |locale|
        described_class::KEYS.reject { |key| I18n.exists?("notifications.keys.#{key}", locale) }
                             .map { |key| "#{locale}: notifications.keys.#{key}" }
      end
      expect(missing).to be_empty, "Add these locale labels: #{missing.join(", ")}"
    end
  end
end
