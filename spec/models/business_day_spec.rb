# frozen_string_literal: true

require "rails_helper"

RSpec.describe BusinessDay do
  # Time.zone is "Cairo" (config.time_zone). Use zone-local timestamps.
  def at(y, m, d, h, min = 0) = Time.zone.local(y, m, d, h, min)

  describe "default 6 AM cutoff" do
    it "defaults start_hour to 6" do
      expect(described_class.start_hour).to eq(6)
    end

    it "assigns post-midnight instants to the previous operating day" do
      expect(described_class.for(at(2026, 1, 10, 1, 0))).to eq(Date.new(2026, 1, 9))   # 1 AM
      expect(described_class.for(at(2026, 1, 10, 4, 0))).to eq(Date.new(2026, 1, 9))   # 4 AM
      expect(described_class.for(at(2026, 1, 10, 5, 59))).to eq(Date.new(2026, 1, 9))  # 5:59 AM
    end

    it "assigns cutoff and later to the new operating day" do
      expect(described_class.for(at(2026, 1, 10, 6, 0))).to eq(Date.new(2026, 1, 10))  # 6 AM sharp
      expect(described_class.for(at(2026, 1, 10, 14, 0))).to eq(Date.new(2026, 1, 10)) # 2 PM
    end

    it "keeps pre-midnight evening on the same operating day" do
      expect(described_class.for(at(2026, 1, 9, 23, 0))).to eq(Date.new(2026, 1, 9))
    end

    it "builds a half-open [cutoff, next-cutoff) range" do
      range = described_class.range(Date.new(2026, 1, 9))
      expect(range).to cover(at(2026, 1, 9, 6, 0))      # start inclusive
      expect(range).to cover(at(2026, 1, 10, 1, 0))     # 1 AM next day still inside
      expect(range).not_to cover(at(2026, 1, 10, 6, 0)) # next cutoff excluded
      expect(range).not_to cover(at(2026, 1, 9, 5, 59)) # before start excluded
    end
  end

  describe "per-company cutoff" do
    it "honours a custom start hour" do
      Setting.set("business_day_start_hour", 4)
      expect(described_class.start_hour).to eq(4)
      expect(described_class.for(at(2026, 1, 10, 3, 0))).to eq(Date.new(2026, 1, 9))   # 3 AM → prev
      expect(described_class.for(at(2026, 1, 10, 5, 0))).to eq(Date.new(2026, 1, 10))  # 5 AM → new
    end
  end
end
