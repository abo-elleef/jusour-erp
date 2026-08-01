# frozen_string_literal: true

require "rails_helper"

RSpec.describe BusinessDay do
  # Time.zone is "Cairo" (config.time_zone). Use zone-local timestamps.
  def at(y, m, d, h, min = 0) = Time.zone.local(y, m, d, h, min)

  describe "default 6 AM cutoff" do
    it "defaults company start_hour to 6" do
      expect(described_class.company_start_hour).to eq(6)
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
      expect(described_class.company_start_hour).to eq(4)
      expect(described_class.for(at(2026, 1, 10, 3, 0))).to eq(Date.new(2026, 1, 9))   # 3 AM → prev
      expect(described_class.for(at(2026, 1, 10, 5, 0))).to eq(Date.new(2026, 1, 10))  # 5 AM → new
    end
  end

  describe "per-branch cutoff override" do
    let(:company) { Current.company }
    let(:branch) { create(:location, company: company, business_day_start_hour: 2) }

    before { Setting.set("business_day_start_hour", 6) }

    it "uses the branch hour when set" do
      expect(described_class.start_hour(location: branch)).to eq(2)
      expect(described_class.for(at(2026, 1, 10, 1, 0), location: branch)).to eq(Date.new(2026, 1, 9))
      expect(described_class.for(at(2026, 1, 10, 2, 0), location: branch)).to eq(Date.new(2026, 1, 10))
    end

    it "falls back to the company hour when the branch has no override" do
      branch.update!(business_day_start_hour: nil)
      expect(described_class.start_hour(location: branch)).to eq(6)
      expect(described_class.for(at(2026, 1, 10, 5, 0), location: branch)).to eq(Date.new(2026, 1, 9))
    end

    it "builds a range with the branch hour" do
      range = described_class.range(Date.new(2026, 1, 9), location: branch)
      expect(range).to cover(at(2026, 1, 9, 2, 0))
      expect(range).not_to cover(at(2026, 1, 10, 2, 0))
    end
  end

  describe "per-branch mode" do
    let(:company) { Current.company }
    let!(:branch) { create(:location, company: company) }

    it "defaults to automatic" do
      expect(described_class.mode(location: branch)).to eq("automatic")
      expect(described_class).to be_automatic(location: branch)
      expect(described_class).not_to be_manual(location: branch)
    end

    it "uses the location operating day when manual" do
      branch.update!(business_day_mode: "manual")
      LocationOperatingDay.ensure_open!(branch, date: Date.new(2026, 3, 1))

      expect(described_class.today(location: branch)).to eq(Date.new(2026, 3, 1))
      expect(described_class.for(Time.current, location: branch)).to eq(Date.new(2026, 3, 1))
      expect(described_class.today).to eq(described_class.clock_today)
    end

    it "bootstraps an operating day when switching to manual" do
      described_class.apply_mode!(branch, "manual")
      expect(described_class).to be_manual(location: branch)
      expect(LocationOperatingDay.current_for(branch).business_date).to eq(described_class.clock_today(location: branch))
    end
  end
end
