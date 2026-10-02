# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "attendance:backfill_audit_history" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  let(:task) { Rake::Task["attendance:backfill_audit_history"] }

  before { task.reenable }

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }
  let(:staff)   { create(:user, company: company) }
  let(:status)  { company.attendance_statuses.find_by!(code: "present") }

  it "gives a pre-existing record with no audit a synthetic first entry using recorded_by/updated_at" do
    record = StaffAttendance.create!(company: company, user: staff, attendance_status: status,
      date: Date.new(2026, 4, 1), recorded_by: owner)
    record.update_column(:updated_at, Time.zone.local(2026, 4, 1, 9, 0))

    expect { task.invoke }.to output(/Backfilled 1\/1/).to_stdout

    entry = AuditLogEntry.where(record_type: "StaffAttendance", record_id: record.id).sole
    expect(entry.action).to eq("create")
    expect(entry.user).to eq(owner)
    expect(entry.created_at).to eq(Time.zone.local(2026, 4, 1, 9, 0))
    expect(entry.changes_snapshot).to eq({ "attendance_status_id" => [nil, status.id] })
  end

  it "leaves a record that already has audit history alone" do
    record = StaffAttendance.create!(company: company, user: staff, attendance_status: status,
      date: Date.new(2026, 4, 1), recorded_by: owner)
    AuditLogEntry.record!(action: "create", record: record, user: owner,
      changes_snapshot: { "attendance_status_id" => [nil, status.id] })

    expect { task.invoke }.to output(/already has at least one audit entry/).to_stdout
    expect(AuditLogEntry.where(record_type: "StaffAttendance", record_id: record.id).count).to eq(1)
  end

  it "is safe to run twice" do
    StaffAttendance.create!(company: company, user: staff, attendance_status: status,
      date: Date.new(2026, 4, 1), recorded_by: owner)

    task.invoke
    task.reenable

    expect { task.invoke }.to output(/already has at least one audit entry/).to_stdout
      .and change(AuditLogEntry, :count).by(0)
  end

  it "backfills across every company, not just the current one" do
    other_company = create(:company)
    other_staff = create(:user, company: other_company)
    other_status = other_company.attendance_statuses.find_by!(code: "present")
    other_record = StaffAttendance.create!(company: other_company, user: other_staff,
      attendance_status: other_status, date: Date.new(2026, 4, 1))

    StaffAttendance.create!(company: company, user: staff, attendance_status: status,
      date: Date.new(2026, 4, 1), recorded_by: owner)

    expect { task.invoke }.to output(/Backfilled 2\/2/).to_stdout
    expect(AuditLogEntry.unscoped.where(record_type: "StaffAttendance", record_id: other_record.id)).to exist
  end
end
