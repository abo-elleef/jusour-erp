# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POS tables board", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:cafe) { create(:location, company: company, name: "Cafe", table_service: true, table_count: 6) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:other_cashier) { create(:user, company: company, role: "cashier") }

  before do
    Current.company = company
    sign_in cashier
    open_drawer_for(cashier, location: cafe)
  end

  def table_order(owner: cashier, table: "3", status: "draft")
    order = create(:order, user: owner, company: company, location: cafe,
                           order_type: "table", table_number: table, status: status)
    create(:order_item, order: order)
    order.recalculate_totals!
    order
  end

  it "shows busy and free tables with the open order's number" do
    order = table_order
    get pos_tables_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("##{order.order_number}")
    expect(response.body).to include(I18n.t("pos.tables.summary", busy: 1, free: 5))
  end

  it "shows both orders when an offline sync put a second one on the table" do
    first = table_order(status: "submitted")
    second = create(:order, user: other_cashier, company: company, location: cafe, order_type: "table",
                            table_number: "3", status: "submitted", offline_number: "OFF-B4", allow_table_clash: true)
    create(:order_item, order: second)

    get pos_tables_path

    expect(response.body).to include("##{first.order_number}", "##{second.order_number}", "OFF-B4")
    expect(response.body).to include(I18n.t("pos.tables.clash", count: 2))
    expect(response.body).to include(I18n.t("pos.tables.summary", busy: 1, free: 5))
  end

  it "is not available at a branch without table service" do
    cafe.update!(table_service: false)
    get pos_tables_path
    expect(response).to redirect_to(pos_path)
  end

  it "starts a new order on a free table" do
    expect { post pos_open_table_path(number: 2) }.to change(Order, :count).by(1)

    expect(Order.last).to have_attributes(order_type: "table", table_number: "2", status: "draft", location_id: cafe.id)
    expect(response).to redirect_to(pos_path)
  end

  it "picks up a busy table's draft for another cashier" do
    order = table_order(owner: other_cashier)

    expect { post pos_open_table_path(number: 3) }.not_to change(Order, :count)

    expect(response).to redirect_to(pos_path)
    expect(session[:current_order_id]).to eq(order.id)
  end

  it "lets a cashier resume another cashier's table draft but not an ordinary one" do
    table = table_order(owner: other_cashier)
    pickup = create(:order, user: other_cashier, company: company, location: cafe, order_type: "pickup", status: "draft")
    create(:order_item, order: pickup)

    post resume_pos_order_path(table)
    expect(response).to redirect_to(pos_path)

    post resume_pos_order_path(pickup)
    expect(session[:current_order_id]).not_to eq(pickup.id)
  end

  it "clears a paid table, freeing it" do
    order = table_order(status: "submitted")
    allow_any_instance_of(Order).to receive(:fully_paid?).and_return(true)

    post complete_pos_order_path(order, from: "tables")

    expect(response).to redirect_to(pos_tables_path)
    expect(order.reload.status).to eq("completed")
    expect(Order.busy_tables(cafe)).to eq({})
  end

  it "rejects moving an order onto a busy table and keeps its own table" do
    table_order(owner: other_cashier, table: "3")
    mine = create(:order, user: cashier, company: company, location: cafe, order_type: "table", table_number: "4")
    create(:order_item, order: mine)
    post resume_pos_order_path(mine)

    patch "/pos/fulfillment", params: { order_type: "table", table_number: "3" }, as: :turbo_stream

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("order.errors.table_busy", table: "3", number: Order.busy_tables(cafe)["3"].order_number))
    expect(mine.reload.table_number).to eq("4")
  end

  it "refuses the first item when another register took the table in the meantime" do
    item = create(:menu_item, company: company)
    LocationMenuItem.create!(location: cafe, menu_item: item, available: true)
    mine = create(:order, user: cashier, company: company, location: cafe, order_type: "table", table_number: "3")
    post resume_pos_order_path(mine)
    Current.company = company # a request resets it
    other = table_order(owner: other_cashier, table: "3")

    expect { post pos_order_items_path, params: { menu_item_id: item.id } }.not_to change(OrderItem, :count)

    expect(response).to redirect_to(pos_path)
    expect(flash[:alert]).to include(other.order_number)
  end

  it "keeps adding items to an order that already holds a table, even if a duplicate exists" do
    item = create(:menu_item, company: company)
    LocationMenuItem.create!(location: cafe, menu_item: item, available: true)
    mine = table_order(owner: cashier, table: "3")
    Order.insert_all!([mine.attributes.except("id", "order_number", "receipt_token").merge(
      "id" => SecureRandom.uuid, "order_number" => "900", "receipt_token" => SecureRandom.hex(8)
    )]) # a second open order on the table, as data from before table service would have
    dup = Order.unscoped.find_by(order_number: "900")
    create(:order_item, order: dup)
    post resume_pos_order_path(mine)
    Current.company = company

    expect { post pos_order_items_path, params: { menu_item_id: item.id }, as: :turbo_stream }
      .to change { mine.order_items.count }.by(1)
    expect(response).to have_http_status(:ok)
  end
end
