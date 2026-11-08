# frozen_string_literal: true

require "rails_helper"

# A shared branch print job reaches every open register. Exactly one may print it.
RSpec.describe PrintLog, "claiming" do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:branch) { create(:location, company: company) }
  let(:order) { create(:order, user: user, company: company, location: branch) }
  let(:log) { PrintLog.create!(order: order, print_type: "station", status: "pending") }

  before { Current.company = company }

  it "gives the job to the first register and refuses the rest" do
    expect(described_class.claim!(log.id, "register-a")).to be(true)
    expect(described_class.claim!(log.id, "register-b")).to be(false)
  end

  it "lets the holder ask again, so its retries are not refused" do
    described_class.claim!(log.id, "register-a")
    expect(described_class.claim!(log.id, "register-a")).to be(true)
  end

  it "frees a claim that has gone stale, so a dead register does not strand the job" do
    described_class.claim!(log.id, "register-a")
    log.update_columns(claimed_at: (PrintLog::CLAIM_TTL + 1.second).ago)

    expect(described_class.claim!(log.id, "register-b")).to be(true)
  end

  it "refuses a job that is already finished" do
    log.update!(status: "sent")
    expect(described_class.claim!(log.id, "register-a")).to be(false)
  end

  it "leaves claimed jobs out of recovery until the claim expires" do
    described_class.claim!(log.id, "register-a")
    expect(described_class.unclaimed).not_to include(log)

    log.update_columns(claimed_at: (PrintLog::CLAIM_TTL + 1.second).ago)
    expect(described_class.unclaimed).to include(log)
  end
end
