# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin location online ordering settings", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:branch) { create(:location, company: company, public_menu_enabled: true) }

  before do
    Current.company = company
    sign_in owner
  end

  it "shows the online ordering section on a branch's edit page" do
    branch.update!(online_open_time: "18:00", online_close_time: "02:00")

    get edit_admin_location_path(branch)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin.locations.online_ordering.heading"))
    expect(response.body).to include('value="18:00"', 'value="02:00"')
    expect(response.body).to include(admin_location_delivery_areas_path(branch))
  end

  it "saves the online ordering settings" do
    patch admin_location_path(branch), params: {
      location: {
        online_ordering_enabled: "1", online_open_time: "18:00", online_close_time: "02:00",
        online_accept_timeout_minutes: "7", online_max_order_pounds: "750"
      }
    }

    expect(response).to redirect_to(admin_location_path(branch))
    branch.reload
    expect(branch.online_ordering_enabled).to be(true)
    expect(branch.online_open_time.strftime("%H:%M")).to eq("18:00")
    expect(branch.online_close_time.strftime("%H:%M")).to eq("02:00")
    expect(branch.online_accept_timeout_minutes).to eq(7)
    expect(branch.online_max_order_cents).to eq(75_000)
  end

  it "clears the hours and the cap when left blank" do
    branch.update!(online_open_time: "10:00", online_close_time: "22:00", online_max_order_cents: 1000)

    patch admin_location_path(branch), params: {
      location: { online_open_time: "", online_close_time: "", online_max_order_pounds: "" }
    }

    branch.reload
    expect(branch.online_open_time).to be_nil
    expect(branch.online_close_time).to be_nil
    expect(branch.online_max_order_cents).to be_nil
  end

  it "refuses only one of the two hours" do
    patch admin_location_path(branch), params: { location: { online_open_time: "10:00", online_close_time: "" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include(I18n.t("admin.locations.online_ordering.errors.hours_both_or_neither"))
  end

  it "saves which payment methods are offered and which must be paid first" do
    get edit_admin_location_path(branch)
    expect(Nokogiri::HTML(response.body).css("input[name$='[payment_method]']").map { |i| i["value"] })
      .to eq(%w[cash instapay vodafone_cash])

    patch admin_location_path(branch), params: {
      location: {
        online_payment_methods_attributes: {
          "0" => { payment_method: "cash", enabled: "0" },
          "1" => { payment_method: "instapay", enabled: "1", requires_proof: "1", pay_to: "saqr@instapay" },
          "2" => { payment_method: "vodafone_cash", enabled: "1", requires_proof: "0" }
        }
      }
    }

    expect(response).to redirect_to(admin_location_path(branch))
    offered = branch.reload.offered_online_payment_methods
    expect(offered.map(&:payment_method)).to eq(%w[instapay vodafone_cash])
    expect(offered.first).to have_attributes(requires_proof: true, pay_to: "saqr@instapay")

    # Saving again updates the same rows.
    instapay = offered.first
    patch admin_location_path(branch), params: {
      location: { online_payment_methods_attributes: { "0" => { id: instapay.id, payment_method: "instapay", enabled: "1", requires_proof: "0" } } }
    }
    expect(instapay.reload.requires_proof).to be(false)
    expect(branch.online_payment_methods.count).to eq(3)
  end

  it "refuses to turn every payment method off" do
    patch admin_location_path(branch), params: {
      location: { online_payment_methods_attributes: { "0" => { payment_method: "cash", enabled: "0" } } }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include(I18n.t("admin.locations.online_ordering.errors.no_payment_method"))
  end
end
