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
end
