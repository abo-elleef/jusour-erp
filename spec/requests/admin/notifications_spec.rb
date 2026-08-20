# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Notifications", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  # A superset of interpolation args so any message_key renders cleanly; each
  # template picks only the ones it needs.
  DEFAULT_PARAMS = {
    on_hand: 3, unit: "kg", threshold: 5,
    direction: "up", old_price_cents: 100, new_price_cents: 130, percent: 30.0,
    supplier: "Acme", invoice_number: "VI-1",
    variance_cents: 250, session_date: "2026-08-20"
  }.freeze

  def notify!(type:, key:, name:, created_at: Time.current, read_at: nil)
    Notification.create!(
      recipient: owner, company: company, notification_type: type, read_at: read_at,
      created_at: created_at,
      params: { message_key: key, message_params: DEFAULT_PARAMS.merge(name: name) }
    )
  end

  it "renders for an admin with the filter controls" do
    notify!(type: "inventory", key: "low_stock", name: "Tomatoes")

    get admin_notifications_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("notifications.index.filters.alert_label"))
    expect(response.body).to include(I18n.t("notifications.index.filters.type_label"))
    expect(response.body).to include(I18n.t("notifications.index.filters.from"))
    expect(response.body).to include(I18n.t("notifications.index.filters.to"))
  end

  it "filters by alert (message_key)" do
    notify!(type: "inventory", key: "low_stock", name: "AlphaLow")
    notify!(type: "inventory", key: "price_change", name: "BetaPrice")

    get admin_notifications_path(alert: "price_change")

    expect(response.body).to include("BetaPrice")
    expect(response.body).not_to include("AlphaLow")
  end

  it "filters by type" do
    notify!(type: "inventory", key: "low_stock", name: "InvItem")
    notify!(type: "accounting", key: "cash_variance", name: "AcctItem")

    get admin_notifications_path(type: "accounting")

    expect(response.body).to include("AcctItem")
    expect(response.body).not_to include("InvItem")
  end

  it "filters by a from/to date range on created_at" do
    notify!(type: "inventory", key: "low_stock", name: "OldOne", created_at: 10.days.ago)
    notify!(type: "inventory", key: "low_stock", name: "NewOne", created_at: Time.current)

    get admin_notifications_path(from: 3.days.ago.to_date.to_s, to: Date.current.to_s)

    expect(response.body).to include("NewOne")
    expect(response.body).not_to include("OldOne")
  end

  it "sorts by time ascending when asked" do
    notify!(type: "inventory", key: "low_stock", name: "EarlyItem", created_at: 5.days.ago)
    notify!(type: "inventory", key: "low_stock", name: "LateItem", created_at: 1.day.ago)

    get admin_notifications_path(sort: "time", dir: "asc")

    expect(response.body.index("EarlyItem")).to be < response.body.index("LateItem")
  end

  it "defaults to newest-first" do
    notify!(type: "inventory", key: "low_stock", name: "EarlyItem", created_at: 5.days.ago)
    notify!(type: "inventory", key: "low_stock", name: "LateItem", created_at: 1.day.ago)

    get admin_notifications_path

    expect(response.body.index("LateItem")).to be < response.body.index("EarlyItem")
  end

  it "paginates at 50 per page" do
    60.times { |i| notify!(type: "inventory", key: "low_stock", name: "Item#{i}", created_at: i.hours.ago) }

    get admin_notifications_path
    expect(response.body).to include("Item0")       # newest, page 1
    expect(response.body).not_to include("Item55")  # spills to page 2

    get admin_notifications_path(page: 2)
    expect(response.body).to include("Item55")
  end

  it "denies non-admin users" do
    cashier = create(:user, role: "cashier", company: company)
    sign_in cashier

    get admin_notifications_path
    expect(response).to redirect_to(pos_path)
  end
end
