# frozen_string_literal: true

require "rails_helper"

RSpec.describe AttendanceStatus do
  let(:company) { Current.company }

  it "requires code, symbol and label" do
    status = described_class.new(company: company, paid_fraction: 1, penalty_days: 0)
    expect(status).not_to be_valid
    expect(status.errors.attribute_names).to include(:code, :symbol, :label)
  end

  it "rejects paid_fraction above 1 or below 0" do
    expect(build(:attendance_status, paid_fraction: 1.5)).not_to be_valid
    expect(build(:attendance_status, paid_fraction: -0.1)).not_to be_valid
    expect(build(:attendance_status, paid_fraction: 0.5)).to be_valid
  end

  it "enforces unique code and symbol per company" do
    create(:attendance_status, code: "custom", symbol: "Z")
    expect { create(:attendance_status, code: "custom", symbol: "Q") }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect { create(:attendance_status, code: "other", symbol: "Z") }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  describe ".seed_defaults!" do
    it "creates P/O/A/X once and is idempotent" do
      described_class.seed_defaults!(company)
      described_class.seed_defaults!(company)

      expect(company.attendance_statuses.pluck(:symbol)).to match_array(%w[P PP O H A X])
      x = company.attendance_statuses.find_by(code: "unexcused")
      expect(x.paid_fraction).to eq(0)
      expect(x.penalty_days).to eq(1)
    end
  end

  it "seeds defaults automatically for a new company" do
    new_company = create(:company)
    expect(new_company.attendance_statuses.pluck(:symbol)).to match_array(%w[P PP O H A X])
  end
end
