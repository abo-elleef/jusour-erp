# frozen_string_literal: true

require "rails_helper"

# Where a branch's takings go is the branch's decision, made once by an admin.
# The cashier counts the drawer; they do not choose the destination.
RSpec.describe "Banking the drawer at close", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let!(:drawer) do
    Treasury.create!(company: company, name: "Front Register", treasury_type: "cash_drawer",
      balance_cents: 0, opening_balance_cents: 0)
  end
  let!(:branch_safe) do
    Treasury.create!(company: company, name: "Branch Safe", treasury_type: "safe",
      balance_cents: 100_000, opening_balance_cents: 100_000)
  end

  before do
    Current.company = company
    cashier.update!(assigned_treasury: drawer)
    sign_in cashier
    post open_drawer_pos_shift_path, params: { opening_float: "100.00" }
    Current.company = company
  end

  def session_for_cashier
    Current.company = company
    cashier.todays_cash_drawer_session(location: branch)
  end

  def close_drawer!
    patch reconcile_pos_shift_path, params: { counted_cash: "100.00" }
    Current.company = company
  end

  describe "when the branch has a treasury of its own" do
    before do
      branch.update!(deposit_treasury: branch_safe)
      close_drawer!
    end

    it "empties the drawer into it" do
      expect(drawer.reload.balance_cents).to eq(0)
      # Back where it started: this safe lent the float at open and has it back.
      expect(branch_safe.reload.balance_cents).to eq(100_000)
    end

    it "records both legs and a balanced entry" do
      legs = TreasuryTransaction.where(source_record: session_for_cashier, kind: "drawer_deposit")
      expect(legs.pluck(:amount_cents)).to contain_exactly(-10_000, 10_000)

      entry = JournalEntry.where(source_record: session_for_cashier)
                          .find { |je| je.description.include?(branch_safe.name) }
      expect(entry.lines.sum(:debit_cents)).to eq(entry.lines.sum(:credit_cents))
    end

    it "remembers where the money went" do
      expect(session_for_cashier.deposit_treasury).to eq(branch_safe)
    end
  end

  describe "when the cashier tries to choose for themselves" do
    it "ignores them and uses the branch's treasury" do
      branch.update!(deposit_treasury: branch_safe)
      other = Treasury.create!(company: company, name: "Someone else's safe",
        treasury_type: "safe", balance_cents: 0, opening_balance_cents: 0)

      patch reconcile_pos_shift_path, params: {
        counted_cash: "100.00", deposit_treasury_id: other.id
      }
      Current.company = company

      expect(branch_safe.reload.balance_cents).to eq(100_000)
      expect(other.reload.balance_cents).to eq(0)
    end
  end

  describe "when the branch has no treasury set" do
    let!(:default_treasury) do
      Treasury.create!(company: company, name: "Company Default", treasury_type: "safe",
        balance_cents: 0, opening_balance_cents: 0, is_default: true)
    end

    it "falls back to the company default so the cash still lands somewhere" do
      close_drawer!

      expect(drawer.reload.balance_cents).to eq(0)
      expect(default_treasury.reload.balance_cents).to eq(10_000)
    end

    it "warns the cashier at count-down that this is a stop-gap" do
      get count_pos_shift_path

      expect(response.body).to include(I18n.t("pos.shift.deposit_fallback_title"))
      expect(response.body).to include(default_treasury.name)
    end
  end

  # The company default is assumed to be configured sensibly — that is an admin's
  # job, not this screen's. All this covers is that a missing one is said out loud
  # rather than silently pretending the cash moved.
  describe "when there is no treasury to fall back on" do
    before { allow(Treasury).to receive(:default_treasury).and_return(nil) }

    it "counts the drawer but leaves the cash in it" do
      close_drawer!

      expect(drawer.reload.balance_cents).to eq(10_000)
      expect(session_for_cashier.status).to eq("reconciled")
      expect(session_for_cashier.deposit_treasury).to be_nil
    end

    it "says so plainly" do
      get count_pos_shift_path

      expect(response.body).to include(I18n.t("pos.shift.deposit_missing_title"))
    end
  end

  it "shows the destination without offering a choice" do
    branch.update!(deposit_treasury: branch_safe)

    get count_pos_shift_path

    expect(response.body).to include(branch_safe.name)
    expect(response.body).not_to include("select name=\"deposit_treasury_id\"")
    expect(response.body).not_to include(I18n.t("pos.shift.deposit_fallback_title"))
  end
end
