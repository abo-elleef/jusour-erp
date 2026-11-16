# frozen_string_literal: true

require "rails_helper"

# A placed order can be voided at the register with the branch's six-digit
# void-orders PIN. It is a separate PIN from the four-digit edit-orders one, and
# voiding does what the admin void does: cancel, put stock back, refund.
RSpec.describe "Voiding an order with the branch PIN", type: :request do
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) do
    create(:location, company: company, name: "Main Branch").tap do |l|
      l.update!(edit_orders_pin: "864213", void_orders_pin: "135790")
    end
  end
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:menu_item) { create(:menu_item, company: company) }

  let!(:drawer) { open_drawer_for(cashier, location: branch) }

  before do
    Current.company = company
    sign_in cashier
    allow_any_instance_of(MenuItem).to receive(:available_at_location?).and_return(true)
    get pos_path
  end

  def place_new_order
    post pos_order_items_path(menu_item_id: menu_item.id), as: :turbo_stream
    order = Order.find(session[:current_order_id])
    patch pos_submit_path
    order.reload
  end

  describe "the branch PIN" do
    it "must be exactly six digits" do
      expect(branch.update(void_orders_pin: "1234")).to be(false)
      expect(branch.errors[:void_orders_pin]).to be_present
      expect(branch.reload.update(void_orders_pin: "246800")).to be(true)
    end

    it "is six digits for the edit-orders PIN too" do
      expect(branch.update(edit_orders_pin: "4321")).to be(false)
      expect(branch.errors[:edit_orders_pin]).to be_present
      expect(branch.reload.update(edit_orders_pin: "112233")).to be(true)
    end

    it "is not the edit-orders PIN" do
      order = place_new_order

      post void_pos_order_path(order), params: { pin: "864213" }

      expect(flash[:alert]).to eq(I18n.t("flash.pos.unlock.wrong_pin"))
      expect(order.reload.status).not_to eq("cancelled")
    end
  end

  it "shows Void order on a placed order's page" do
    order = place_new_order

    get pos_order_path(order)

    expect(response.body).to include(%(id="void-order-dialog-#{order.id}"))
    expect(response.body).to include(void_pos_order_path(order))
  end

  # A type="password" field makes the browser offer to save the PIN, and a named
  # text field lands in form-autocomplete history: either way the next person at
  # the till could get it back. The typed box has no name and a fresh id each
  # time; the PIN is posted from a hidden field.
  it "asks for the PINs in boxes no browser can remember" do
    order = place_new_order
    branch.update!(edit_orders_pin: "864213")
    order.update_columns(unlocked_for_edit_at: nil)

    get pos_order_path(order)

    expect(response.body).not_to include('type="password"')
    doc = Nokogiri::HTML(response.body)
    expect(doc.css('input[name="pin"]').map { |i| i["type"] }).to eq(%w[hidden hidden])

    # The two dialogs' boxes, plus the layout's manager-PIN popup.
    boxes = doc.css("input.pin-mask")
    expect(boxes.size).to eq(3)
    boxes.each do |box|
      expect(box["name"]).to be_nil
      expect(box["type"]).to eq("text")
      expect(box["autocomplete"]).to eq("off")
    end

    get pos_order_path(order)
    ids = boxes.map { |b| b["id"] }.compact
    expect(ids.size).to eq(2)
    expect(Nokogiri::HTML(response.body).css("input.pin-mask").map { |b| b["id"] }).not_to include(*ids)
  end

  it "refuses a wrong PIN and leaves the order alone" do
    order = place_new_order

    post void_pos_order_path(order), params: { pin: "000000" }

    expect(response).to redirect_to(pos_order_path(order))
    expect(flash[:alert]).to eq(I18n.t("flash.pos.unlock.wrong_pin"))
    expect(order.reload.status).to eq("submitted")
  end

  it "locks the PIN after five wrong tries, without touching the edit PIN" do
    order = place_new_order

    5.times { post void_pos_order_path(order), params: { pin: "000000" } }
    post void_pos_order_path(order), params: { pin: "135790" }

    expect(flash[:alert]).to eq(I18n.t("flash.pos.unlock.pin_locked"))
    expect(order.reload.status).to eq("submitted")
    expect(branch.reload.edit_orders_pin_locked?).to be(false)
  end

  it "says so when the branch has no void PIN" do
    order = place_new_order
    branch.update_columns(void_orders_pin_digest: nil)

    post void_pos_order_path(order), params: { pin: "135790" }

    expect(flash[:alert]).to eq(I18n.t("flash.pos.void.pin_not_set"))
  end

  it "with the right PIN, voids the order and records who did it" do
    order = place_new_order

    post void_pos_order_path(order), params: { pin: "135790", reason: "Customer left" }

    expect(response).to redirect_to(pos_order_path(order))
    expect(flash[:notice]).to eq(I18n.t("flash.order.voided"))
    expect(order.reload.status).to eq("cancelled")
    expect(order.order_events.where(event_type: "void", description: "Customer left")).to exist
    expect(AuditLogEntry.where(action: "order.void_with_pin", record_id: order.id)).to exist
  end

  describe "a paid order" do
    def pay(order, session:)
      create(:payment, order: order, company: company, amount_cents: 5000, status: "completed",
                       payment_method: "cash", cash_drawer_session: session)
    end

    it "is voided and refunded while the drawer that took the money is still open" do
      order = place_new_order
      payment = pay(order, session: drawer)

      post void_pos_order_path(order), params: { pin: "135790" }

      expect(order.reload.status).to eq("cancelled")
      expect(payment.reload.status).to eq("refunded")
    end

    it "is voided and refunded after it was completed, too" do
      order = place_new_order
      payment = pay(order, session: drawer)
      order.update_columns(status: "completed")

      get pos_order_path(order)
      expect(response.body).to include(%(id="void-order-dialog-#{order.id}"))

      post void_pos_order_path(order), params: { pin: "135790" }

      expect(order.reload.status).to eq("cancelled")
      expect(payment.reload.status).to eq("refunded")
      expect(flash[:notice]).to be_present
    end

    # Refunding would rewrite the counted drawer's expected cash after its count.
    it "is refused once that drawer is closed, and sent to the admin side" do
      order = place_new_order
      payment = pay(order, session: drawer)
      drawer.update_columns(status: "counted")
      open_drawer_for(cashier, location: branch)

      get pos_order_path(order)
      expect(response.body).not_to include(%(id="void-order-dialog-#{order.id}"))
      expect(response.body).to include(CGI.escapeHTML(I18n.t("pos.orders.blocked.void.closed_drawer")))

      post void_pos_order_path(order), params: { pin: "135790" }

      expect(response).to redirect_to(pos_order_path(order))
      expect(flash[:alert]).to eq(I18n.t("flash.pos.void.drawer_closed"))
      expect(order.reload.status).not_to eq("cancelled")
      expect(payment.reload.refunded_amount_cents).to eq(0)
    end

    it "is still voidable from admin after the drawer closed" do
      order = place_new_order
      pay(order, session: drawer)
      drawer.update_columns(status: "reconciled")

      result = Orders::VoidService.call(order: order, user: cashier, open_drawers_only: true)
      expect(result.voided?).to be(false)
      expect(result.error).to eq(:drawer_closed)

      expect(Orders::VoidService.call(order: order.reload, user: cashier).error).to eq(:treasury_required)

      Current.company = company
      safe = Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                              balance_cents: 0, opening_balance_cents: 0)
      expect(Orders::VoidService.call(order: order.reload, user: cashier, refund_treasury: safe).voided?).to be(true)
    end
  end

  describe "buttons the rules refuse stay on the order page, greyed out with why" do
    it "explains Edit items on a paid order" do
      order = place_new_order
      create(:payment, order: order, company: company, amount_cents: order.total_cents, status: "completed",
                       payment_method: "cash", cash_drawer_session: drawer)

      get pos_order_path(order)

      expect(response.body).not_to include(%(id="unlock-edit-dialog-#{order.id}"))
      expect(response.body).to include(CGI.escapeHTML(I18n.t("pos.orders.blocked.edit_items.paid")))
      expect(response.body).to include(%(aria-disabled="true"))
    end

    it "explains Edit items on a completed unpaid order" do
      order = place_new_order
      order.update_columns(status: "completed")

      get pos_order_path(order)

      expect(response.body).to include(CGI.escapeHTML(I18n.t("pos.orders.blocked.edit_items.completed")))
    end

    it "explains both on a voided order" do
      order = place_new_order
      post void_pos_order_path(order), params: { pin: "135790" }
      expect(order.reload.status).to eq("cancelled")

      get pos_order_path(order)
      expect(response).to have_http_status(:ok)

      expect(response.body).not_to include(%(id="void-order-dialog-#{order.id}"))
      expect(response.body).to include(CGI.escapeHTML(I18n.t("pos.orders.blocked.void.cancelled")))
      expect(response.body).to include(CGI.escapeHTML(I18n.t("pos.orders.blocked.edit_items.cancelled")))
    end
  end

  it "does not offer it on a draft or an already cancelled order" do
    post pos_order_items_path(menu_item_id: menu_item.id), as: :turbo_stream
    draft = Order.find(session[:current_order_id])

    post void_pos_order_path(draft), params: { pin: "135790" }
    expect(draft.reload.status).to eq("draft")
  end
end
