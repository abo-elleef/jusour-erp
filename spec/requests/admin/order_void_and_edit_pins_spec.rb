# frozen_string_literal: true

require "rails_helper"

# The admin order page: anyone who can open it may void or reopen an order. Owners
# and managers go straight through; everyone else types the branch's PIN. Money a
# closed drawer took in is refunded by a payment voucher from a treasury the admin
# picks, so the counted shift is left as it was.
RSpec.describe "Admin order page: void and edit with branch PINs", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 6, 10, 14, 0, 0)) { example.run } }

  let(:company) { create(:company) }
  let!(:branch) do
    create(:location, company: company, name: "Cafe").tap do |l|
      l.update!(edit_orders_pin: "864213", void_orders_pin: "135790")
    end
  end
  let(:owner) { create(:user, :owner, company: company) }
  let(:manager) { create(:user, :manager, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier", name: "Sayed") }
  # Staff who can open admin orders and work the register, but are not managers.
  let(:supervisor) do
    role = Role.create!(company: company, name: "Supervisor", key: "supervisor",
                        permissions: %w[orders:view pos:access])
    create(:user, company: company, role: "custom", role_id: role.id)
  end
  let!(:till) do
    Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0)
  end
  let!(:safe) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                     balance_cents: 0, opening_balance_cents: 0)
  end
  let!(:drawer) do
    CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                              session_date: Date.current, opening_float_cents: 0, status: "open",
                              deposit_treasury: safe)
  end
  let(:menu_item) { create(:menu_item, company: company) }

  before { Current.company = company }

  def placed_order
    Current.company = company
    order = create(:order, user: cashier, company: company, location: branch, status: "submitted",
                           order_type: "pickup")
    create(:order_item, order: order, menu_item: menu_item, quantity: 1, unit_price_cents: 5_000)
    order.recalculate_totals!
    order.reload
  end

  def pay(order, amount: 5_000)
    create(:payment, order: order, company: company, amount_cents: amount, status: "completed",
                     payment_method: "cash", processed_by_user: cashier, cash_drawer_session_id: drawer.id)
  end

  def close_drawer!
    Current.company = company
    Accounting::CashReconciliationService.new(drawer.reload).reconcile!(5_000, by: owner)
    drawer.reload
  end

  def account_balance(code)
    lines = JournalEntryLine.joins(:journal_entry)
                            .where(journal_entries: { company_id: company.id }, account_code: code)
    lines.sum(:debit_cents) - lines.sum(:credit_cents)
  end

  describe "voiding" do
    it "lets a manager void without a PIN" do
      order = placed_order
      sign_in manager

      post void_admin_order_path(order), params: { reason: "Customer left" }

      expect(order.reload).to be_cancelled
    end

    it "asks anyone else for the branch void PIN" do
      order = placed_order
      sign_in supervisor

      post void_admin_order_path(order), params: { pin: "000000" }
      expect(flash[:alert]).to eq(I18n.t("flash.pos.unlock.wrong_pin"))
      expect(order.reload).not_to be_cancelled

      post void_admin_order_path(order), params: { pin: "135790" }
      expect(order.reload).to be_cancelled
      expect(AuditLogEntry.where(action: "order.void_with_pin", record_id: order.id)).to exist
    end

    it "shows the PIN field to non-managers only" do
      order = placed_order

      sign_in supervisor
      get admin_order_path(order)
      expect(response.body).to include(%(id="void_pin"))

      sign_in manager
      get admin_order_path(order)
      expect(response.body).not_to include(%(id="void_pin"))
    end

    it "refunds on the payment while the paying drawer is still open" do
      order = placed_order
      payment = pay(order)
      sign_in manager

      post void_admin_order_path(order)

      expect(order.reload).to be_cancelled
      expect(payment.reload.status).to eq("refunded")
      expect(order.refund_vouchers).to be_empty
    end

    context "when the paying drawer is closed" do
      let!(:order) { placed_order }
      let!(:payment) { pay(order) }

      before { close_drawer! }

      it "offers the treasury the cash went to" do
        sign_in manager

        get admin_order_path(order)

        expect(response.body).to include(%(name="refund_treasury_id"))
        expect(response.body).to match(/<option selected="selected" value="#{safe.id}">Safe<\/option>/)
      end

      it "refuses without a treasury" do
        sign_in manager

        post void_admin_order_path(order)

        expect(flash[:alert]).to eq(I18n.t("flash.order.refund_treasury_required"))
        expect(order.reload).not_to be_cancelled
      end

      it "refunds by a payment voucher and leaves the counted shift alone" do
        expected_before = drawer.expected_cash_cents
        clearing_before = account_balance(Accounting::JournalEntryService::SALES_CLEARING_CODE)
        sign_in manager

        post void_admin_order_path(order), params: { refund_treasury_id: safe.id, reason: "Wrong order" }

        expect(order.reload).to be_cancelled
        expect(payment.reload.refunded_amount_cents).to eq(0)
        expect(drawer.reload.expected_cash_cents).to eq(expected_before)

        voucher = order.refund_vouchers.sole
        expect(voucher).to be_payment
        expect(voucher.treasury).to eq(safe)
        expect(voucher.amount_cents).to eq(5_000)
        expect(safe.reload.balance_cents).to eq(0) # banked 50 at close, paid 50 back
        expect(account_balance(Accounting::JournalEntryService::SALES_CLEARING_CODE))
          .to eq(clearing_before + 5_000)
        expect(flash[:notice]).to include(voucher.number)

        get admin_order_path(order)
        expect(response.body).to include(voucher.number)
      end

      it "keeps the refund voucher from being voided on its own" do
        sign_in manager
        post void_admin_order_path(order), params: { refund_treasury_id: safe.id }

        expect(VoucherPolicy.new(owner, order.reload.refund_vouchers.sole).destroy?).to be(false)
      end
    end
  end

  describe "Edit items" do
    it "reopens the order in the register at its branch, without a PIN for a manager" do
      order = placed_order
      sign_in manager

      post unlock_edit_admin_order_path(order)

      expect(response).to redirect_to(pos_path)
      expect(order.reload).to be_editing_placed
      expect(session[:current_order_id]).to eq(order.id)
      expect(session[:pos_location_id]).to eq(branch.id)
    end

    it "needs the branch edit PIN from anyone else" do
      order = placed_order
      sign_in supervisor

      get admin_order_path(order)
      expect(response.body).to include(%(id="admin-unlock-edit-dialog-#{order.id}"))

      post unlock_edit_admin_order_path(order), params: { pin: "000000" }
      expect(order.reload).not_to be_editing_placed

      post unlock_edit_admin_order_path(order), params: { pin: "864213" }
      expect(order.reload).to be_editing_placed
    end

    it "is refused for someone who does not work at the order's branch" do
      order = placed_order
      manager.update!(all_locations: false)
      sign_in manager

      post unlock_edit_admin_order_path(order)

      expect(flash[:alert]).to eq(I18n.t("flash.order.edit_branch_not_allowed"))
      expect(order.reload).not_to be_editing_placed
    end

    it "is not offered once the order is paid" do
      order = placed_order
      pay(order)
      sign_in manager

      get admin_order_path(order)

      expect(response.body).not_to include(unlock_edit_admin_order_path(order))
    end
  end
end
