# frozen_string_literal: true

require "rails_helper"

# NOTE: every example here is currently blocked by a pre-existing, unrelated bug:
# `users.wages_account_code` is NOT NULL with no default and nothing in the app
# (no migration, no model/controller code) ever sets it, so `create(:user)` fails
# for any spec on main, not just this one (e.g. spec/models/voucher_numbering_spec.rb
# fails the same way). Left for the user to fix separately — do not work around it
# here. Remove this skip once that's resolved.
RSpec.describe Lead, type: :model,
  skip: "blocked by pre-existing users.wages_account_code NOT NULL bug (no migration/code sets it)" do
  let(:company) { create(:company) }
  let(:creator) { create(:user, company: company) }

  before { Current.company = company }

  describe "validations" do
    it "requires a name" do
      lead = build(:lead, name: nil, created_by: creator)
      expect(lead).not_to be_valid
      expect(lead.errors[:name]).to be_present
    end

    it "requires a phone or an email" do
      lead = build(:lead, phone: nil, email: nil, created_by: creator)
      expect(lead).not_to be_valid
      expect(lead.errors[:base]).to include(I18n.t("sales.leads.errors.phone_or_email_required"))
    end

    it "is valid with an email only" do
      lead = build(:lead, phone: nil, email: "prospect@test.com", created_by: creator)
      expect(lead).to be_valid
    end

    it "requires a lost_reason when marked lost" do
      lead = build(:lead, created_by: creator, stage: "lost", lost_reason: nil)
      expect(lead).not_to be_valid
      expect(lead.errors[:lost_reason]).to be_present
    end
  end

  describe "#default_assigned_user" do
    it "defaults the assignee to the creator when none is given" do
      lead = create(:lead, created_by: creator, assigned_user: nil)
      expect(lead.assigned_user).to eq(creator)
    end

    it "keeps an explicitly assigned user" do
      other = create(:user, company: company)
      lead = create(:lead, created_by: creator, assigned_user: other)
      expect(lead.assigned_user).to eq(other)
    end
  end

  describe "#change_stage!" do
    it "moves the lead to a non-terminal stage and logs it" do
      lead = create(:lead, created_by: creator, stage: "new")
      lead.change_stage!("contacted", by: creator)

      expect(lead.reload.stage).to eq("contacted")
      expect(lead.lead_activities.first.activity_type).to eq("stage_change")
    end

    it "refuses to be used for terminal stages" do
      lead = create(:lead, created_by: creator)
      expect { lead.change_stage!("converted", by: creator) }.to raise_error(ArgumentError)
    end
  end

  describe "#reassign!" do
    it "changes the assignee and logs the handoff" do
      lead = create(:lead, created_by: creator, assigned_user: creator)
      other = create(:user, company: company)

      lead.reassign!(to: other, by: creator)

      expect(lead.reload.assigned_user).to eq(other)
      activity = lead.lead_activities.first
      expect(activity.activity_type).to eq("assignment_change")
    end
  end

  describe "#convert!" do
    it "creates a customer from the lead's contact details and marks it converted" do
      lead = create(:lead, created_by: creator, name: "Acme Pharmacy", phone: "5551234", email: "acme@test.com")

      customer = lead.convert!(by: creator)

      expect(customer).to be_a(Customer)
      expect(customer.name).to eq("Acme Pharmacy")
      expect(customer.originating_lead).to eq(lead)
      expect(lead.reload).to be_converted
      expect(lead.customer).to eq(customer)
      expect(lead.converted_at).to be_present
    end

    it "is idempotent once converted" do
      lead = create(:lead, created_by: creator)
      first_customer = lead.convert!(by: creator)

      expect(lead.convert!(by: creator)).to eq(first_customer)
    end
  end

  describe "#mark_lost!" do
    it "records the reason and logs it" do
      lead = create(:lead, created_by: creator)
      lead.mark_lost!(by: creator, lost_reason: "price", lost_reason_note: "Too expensive for them")

      lead.reload
      expect(lead).to be_lost
      expect(lead.lost_reason).to eq("price")
      expect(lead.lost_at).to be_present
    end
  end

  describe "scopes" do
    it "#due_for_follow_up returns only open leads due today or earlier" do
      due = create(:lead, created_by: creator, next_follow_up_at: Date.yesterday)
      future = create(:lead, created_by: creator, next_follow_up_at: 1.week.from_now.to_date)
      create(:lead, created_by: creator, next_follow_up_at: Date.current, stage: "lost", lost_reason: "price")

      expect(Lead.due_for_follow_up).to contain_exactly(due)
      expect(Lead.due_for_follow_up).not_to include(future)
    end
  end
end
