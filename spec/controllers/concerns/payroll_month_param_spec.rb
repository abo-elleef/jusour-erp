# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayrollMonthParam do
  describe ".default_payroll_month" do
    it "returns the previous month through the grace period" do
      expect(described_class.default_payroll_month(today: Date.new(2026, 8, 1)))
        .to eq(Date.new(2026, 7, 1))
      expect(described_class.default_payroll_month(today: Date.new(2026, 8, 5)))
        .to eq(Date.new(2026, 7, 1))
    end

    it "returns the current month from the day after the grace period" do
      expect(described_class.default_payroll_month(today: Date.new(2026, 8, 6)))
        .to eq(Date.new(2026, 8, 1))
      expect(described_class.default_payroll_month(today: Date.new(2026, 8, 15)))
        .to eq(Date.new(2026, 8, 1))
    end
  end
end
