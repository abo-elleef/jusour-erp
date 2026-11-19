# frozen_string_literal: true

require "rails_helper"

RSpec.describe Leads::FollowUpNotifier do
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:rep) { create(:user, company: company) }
  let(:other_rep) { create(:user, company: company) }
  let(:creator) { create(:user, company: company) }

  before { Current.company = company }

  def lead_due(on, **attrs)
    create(:lead, created_by: creator, assigned_user: rep, next_follow_up_at: on, **attrs)
  end

  def follow_up_notifications
    Notification.unscoped_by_company.where("params->>'message_key' = ?", described_class::MESSAGE_KEY)
  end

  it "notifies only the assigned user, once per due or overdue lead" do
    today = lead_due(Date.current)
    overdue = lead_due(Date.current - 3)
    lead_due(Date.current + 1)
    create(:lead, created_by: creator, assigned_user: other_rep, next_follow_up_at: Date.current + 5)

    expect(described_class.call(company)).to eq(2)

    expect(follow_up_notifications.pluck(:recipient_id).uniq).to eq([rep.id])
    expect(follow_up_notifications.map { |n| n.params["lead_id"] }).to contain_exactly(today.id, overdue.id)
    n = follow_up_notifications.find_by("params->>'lead_id' = ?", overdue.id)
    expect(n.params["message_params"]).to include("lead_name" => overdue.name, "overdue" => true)
    expect(n.target_path).to eq(Rails.application.routes.url_helpers.admin_sales_lead_path(overdue))
  end

  it "does not send twice on the same day when re-run" do
    lead_due(Date.current)
    described_class.call(company)

    expect(described_class.call(company)).to eq(0)
    expect(follow_up_notifications.count).to eq(1)
  end

  it "sends again on the next day" do
    lead = lead_due(Date.current - 1)
    travel_to(1.day.ago) { described_class.call(company) }

    expect(described_class.call(company)).to eq(1)
    expect(follow_up_notifications.where("params->>'lead_id' = ?", lead.id).count).to eq(2)
  end

  it "skips lost and converted leads" do
    lead_due(Date.current, stage: "lost", lost_reason: "price")
    lead_due(Date.current, stage: "converted")

    expect(described_class.call(company)).to eq(0)
  end

  it "pushes it live to the assigned user" do
    lead_due(Date.current)
    expect { described_class.call(company) }
      .to have_enqueued_job(Notifications::BroadcastJob).with(rep.id, anything, popup: true)
  end

  it "does nothing when the company turned the cadence off" do
    Setting.set("lead_first_follow_up_days", 0)
    Setting.set("lead_follow_up_every_days", 0)
    lead_due(Date.current)

    expect(described_class.call(company)).to eq(0)
    expect(follow_up_notifications).to be_empty
  end

  it "does nothing for a company without the leads feature" do
    lead_due(Date.current)
    company.update!(business_type: "restaurant", feature_overrides: {})

    expect(described_class.call(company)).to eq(0)
  end

  it "only touches its own company's leads" do
    lead_due(Date.current)
    other = create(:company, business_type: "distribution")

    expect(described_class.call(other)).to eq(0)
    expect(Current.company).to eq(company)
  end
end
