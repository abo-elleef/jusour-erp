# frozen_string_literal: true

require "rails_helper"

# A treasury's transaction log linked every VendorInvoice-sourced description
# to the invoice, but a Voucher-sourced row (a plain payment or receipt, with
# no invoice behind it) stayed plain text — the reader had no way to reach the
# سند from the ledger that recorded its cash leg.
RSpec.describe "A voucher-sourced treasury transaction's description", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner)   { create(:user, :owner, company: company) }
  let!(:cash) do
    Treasury.create!(name: "Main Cash", treasury_type: "cash_drawer",
      balance_cents: 100_000, opening_balance_cents: 100_000, company: company)
  end

  before do
    Current.company = company
    sign_in owner
  end

  it "links to the voucher that recorded it" do
    voucher = Accounting::RecordVoucherService.new(
      direction: Voucher::PAYMENT, treasury: cash, user: owner, amount_cents: 1_000,
      purpose: Voucher::EQUITY_ADJUSTMENT, notes: "test payout"
    ).call

    get admin_accounting_treasury_path(cash)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin_accounting_voucher_path(voucher))
  end
end
