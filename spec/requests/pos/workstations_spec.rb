# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POS workstation binding", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company, name: "Downtown") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let!(:printer) do
    Printer.create!(
      company: company,
      location: branch,
      name: "Front USB",
      printer_type: "receipt",
      connection_type: "usb",
      host: "USB001",
      paper_width: "80mm",
      active: true
    )
  end
  let!(:workstation) do
    Workstation.create!(
      company: company,
      location: branch,
      name: "Register A",
      receipt_printer: printer,
      active: true
    )
  end

  before do
    Current.company = company
    sign_in cashier
  end

  it "lets the cashier select a register and stamps it on the draft order" do
    patch pos_set_location_path, params: { location_id: branch.id }
    expect(response).to redirect_to(pos_path)

    patch pos_set_workstation_path, params: { workstation_id: workstation.id }
    expect(response).to redirect_to(pos_path)
    follow_redirect!
    expect(response.body).to include("Register A")

    get pos_path
    expect(session[:pos_workstation_id]).to eq(workstation.id)
  end

  context "when the branch has more than one till" do
    let!(:second_workstation) do
      Workstation.create!(
        company: company,
        location: branch,
        name: "Register B",
        receipt_printer: printer,
        active: true
      )
    end
    let(:other_cashier) { create(:user, company: company, role: "cashier") }

    # A new sign-in on the same device: the session is gone, the device's cookies
    # are not. Devise's test sign_out keeps the integration session, so this resets
    # everything and puts the cookies back by hand.
    def sign_in_on_same_device(user)
      kept = %w[pos_location_id pos_workstation_id].index_with { |name| cookies[name] }.compact
      reset!
      Current.company = company
      kept.each { |name, value| cookies[name] = value }
      sign_in user
    end

    it "reopens on the till this device last picked, whoever signs in" do
      patch pos_set_location_path, params: { location_id: branch.id }
      patch pos_set_workstation_path, params: { workstation_id: second_workstation.id }

      sign_in_on_same_device(other_cashier)
      get pos_path

      expect(session[:pos_workstation_id]).to eq(second_workstation.id)
    end

    it "leaves the till unset when this device never picked one" do
      patch pos_set_location_path, params: { location_id: branch.id }

      sign_in_on_same_device(other_cashier)
      get pos_path

      expect(session[:pos_workstation_id]).to be_nil
    end

    it "ignores the remembered till once the device is in another branch" do
      other_branch = create(:location, company: company, name: "Seaside")
      patch pos_set_location_path, params: { location_id: branch.id }
      patch pos_set_workstation_path, params: { workstation_id: second_workstation.id }

      patch pos_set_location_path, params: { location_id: other_branch.id }
      get pos_path

      expect(session[:pos_workstation_id]).to be_nil
    end
  end
end
