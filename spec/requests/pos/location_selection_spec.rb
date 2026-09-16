# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POS branch selection", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:downtown) { create(:location, company: company, name: "Downtown") }
  let!(:seaside) { create(:location, company: company, name: "Seaside") }
  let(:cashier) { create(:user, company: company, role: "cashier") }

  before do
    Current.company = company
    sign_in cashier
  end

  context "when the cashier can work in every branch" do
    it "offers a blank option rather than showing a branch that is not actually set" do
      get pos_shift_path

      expect(response.body).to include(I18n.t("pos.location.select"))
      expect(session[:pos_location_id]).to be_nil
    end

    it "reopens on the branch this device last used" do
      patch pos_set_location_path, params: { location_id: seaside.id }
      # A fresh sign-in drops the session but not the device's cookie.
      sign_in cashier

      get pos_shift_path

      expect(session[:pos_location_id]).to eq(seaside.id)
      expect(response.body).not_to include(I18n.t("pos.location.select"))
    end
  end

  context "when the cashier is assigned to one branch" do
    before do
      cashier.update!(all_locations: false)
      cashier.locations << downtown
    end

    it "selects that branch on the first visit and hides the picker" do
      get pos_shift_path

      expect(session[:pos_location_id]).to eq(downtown.id)
      expect(response.body).to include("Downtown")
      expect(response.body).not_to include("Seaside")
    end
  end

  context "when a remembered branch is no longer the cashier's to work in" do
    it "falls back to the picker instead of staying selected" do
      patch pos_set_location_path, params: { location_id: seaside.id }

      cashier.update!(all_locations: false)
      cashier.locations << downtown

      get pos_shift_path

      expect(session[:pos_location_id]).to eq(downtown.id)
    end
  end
end
