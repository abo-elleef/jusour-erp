# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffAttendance do
  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:staff) { create(:user, company: company) }
  let(:status) { company.attendance_statuses.find_by!(code: "present") }

  def build_record(**attrs)
    described_class.new(
      { company: company, user: staff, attendance_status: status,
        recorded_by: owner, date: Date.new(2026, 4, 1) }.merge(attrs)
    )
  end

  it "is valid with the required fields" do
    expect(build_record).to be_valid
  end

  it "requires a date" do
    expect(build_record(date: nil)).not_to be_valid
  end

  it "allows only one row per user per day" do
    build_record.save!
    expect(build_record).not_to be_valid
  end

  it "allows the same day for different staff" do
    build_record.save!
    other = create(:user, company: company)
    expect(build_record(user: other)).to be_valid
  end

  it "scopes to a month" do
    build_record(date: Date.new(2026, 4, 10)).save!
    build_record(date: Date.new(2026, 5, 10)).save!
    expect(described_class.for_month(Date.new(2026, 4, 1)).count).to eq(1)
  end
end
