# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Lead follow-up cadence", type: :model do
  let(:company) { create(:company, business_type: "distribution") }
  let(:rep) { create(:user, company: company) }

  before { Current.company = company }

  def set_cadence(first:, every:)
    Setting.set("lead_first_follow_up_days", first)
    Setting.set("lead_follow_up_every_days", every)
  end

  describe "settings" do
    it "defaults to first 1 day and every 3 days when never saved" do
      expect(CompanySetting.current).to be_nil
      expect(Setting.lead_first_follow_up_days).to eq(1)
      expect(Setting.lead_follow_up_every_days).to eq(3)
      expect(Setting.lead_follow_up_cadence?).to be(true)
    end

    it "treats 0 as off" do
      set_cadence(first: 0, every: 0)
      expect(Setting.lead_follow_up_cadence?).to be(false)
    end
  end

  describe "new lead" do
    it "gets created date + first-follow-up days" do
      set_cadence(first: 2, every: 3)
      lead = create(:lead, created_by: rep)
      expect(lead.next_follow_up_at).to eq(Date.current + 2)
    end

    it "keeps a date the rep typed" do
      set_cadence(first: 2, every: 3)
      lead = create(:lead, created_by: rep, next_follow_up_at: Date.current + 10)
      expect(lead.next_follow_up_at).to eq(Date.current + 10)
    end

    it "gets no date when the setting is off" do
      set_cadence(first: 0, every: 3)
      expect(create(:lead, created_by: rep).next_follow_up_at).to be_nil
    end
  end

  describe "logging an activity" do
    let(:lead) { create(:lead, created_by: rep, next_follow_up_at: Date.current - 2) }

    before { set_cadence(first: 1, every: 3) }

    it "moves the next follow-up to the activity date + every-N days" do
      create(:lead_activity, lead: lead, user: rep, activity_type: "call", occurred_at: Time.current)
      expect(lead.reload.next_follow_up_at).to eq(Date.current + 3)
    end

    it "counts from the activity's own date" do
      create(:lead_activity, lead: lead, user: rep, activity_type: "meeting", occurred_at: 1.day.ago)
      expect(lead.reload.next_follow_up_at).to eq(Date.current + 2)
    end

    it "keeps the date the rep picked instead" do
      create(:lead_activity, lead: lead, user: rep, activity_type: "whatsapp",
        next_follow_up_on: Date.current + 7)
      expect(lead.reload.next_follow_up_at).to eq(Date.current + 7)
    end

    it "is audited on the lead" do
      expect do
        create(:lead_activity, lead: lead, user: rep, activity_type: "call")
      end.to change { lead.audits.count }.by(1)
    end

    it "does not move it for system entries" do
      lead.change_stage!("contacted", by: rep)
      lead.reassign!(to: create(:user, company: company), by: rep)
      expect(lead.reload.next_follow_up_at).to eq(Date.current - 2)
    end

    it "does not move it when every-N days is off" do
      set_cadence(first: 1, every: 0)
      create(:lead_activity, lead: lead, user: rep, activity_type: "call")
      expect(lead.reload.next_follow_up_at).to eq(Date.current - 2)
    end

    it "gives a lost lead no next date" do
      lead.mark_lost!(by: rep, lost_reason: "price")
      expect(lead.reload.next_follow_up_at).to be_nil

      create(:lead_activity, lead: lead, user: rep, activity_type: "note")
      expect(lead.reload.next_follow_up_at).to be_nil
    end

    it "gives a converted lead no next date" do
      lead.convert!(by: rep)
      create(:lead_activity, lead: lead, user: rep, activity_type: "call")
      expect(lead.reload.next_follow_up_at).to be_nil
    end
  end
end
