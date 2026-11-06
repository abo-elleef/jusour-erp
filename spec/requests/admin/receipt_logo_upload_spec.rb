# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Uploading receipt logos", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let!(:branch) { create(:location, company: company) }
  let(:png) { fixture_file_upload("storefront_product.png", "image/png") }
  let(:text_file) { fixture_file_upload("not_an_image.txt", "text/plain") }

  before do
    Current.company = company
    sign_in owner
  end

  describe "company logo (settings)" do
    it "stores the upload" do
      patch admin_settings_path, params: { receipt_logo: png }

      expect(response).to redirect_to(admin_settings_path)
      expect(CompanySetting.find_by!(company: company).receipt_logo).to be_attached
    end

    it "removes it when asked" do
      patch admin_settings_path, params: { receipt_logo: png }
      patch admin_settings_path, params: { remove_receipt_logo: "1" }

      expect(CompanySetting.find_by!(company: company).receipt_logo).not_to be_attached
    end

    it "does not touch the logo on an unrelated settings save" do
      patch admin_settings_path, params: { receipt_logo: png }
      patch admin_settings_path, params: { receipt_footer_text: "Thanks!" }

      expect(CompanySetting.find_by!(company: company).receipt_logo).to be_attached
    end

    it "rejects a non-image with a message and keeps the old logo" do
      patch admin_settings_path, params: { receipt_logo: png }
      patch admin_settings_path, params: { receipt_logo: text_file }

      expect(response).to redirect_to(admin_settings_path)
      expect(flash[:alert]).to be_present
      expect(CompanySetting.find_by!(company: company).receipt_logo.filename.to_s).to eq("storefront_product.png")
    end

    it "shows the control on the settings page" do
      get admin_settings_path

      expect(response.body).to include('data-testid="receipt-logo-field"')
    end

    # Browsers only send the file bytes when the form is multipart.
    it "renders a multipart form" do
      get admin_settings_path

      expect(response.body).to match(/<form[^>]*enctype="multipart\/form-data"[^>]*>(?:(?!<\/form>).)*receipt_logo/m)
    end
  end

  describe "branch logo (location form)" do
    it "stores and then removes the branch logo" do
      patch admin_location_path(branch), params: { location: { receipt_logo: png } }
      expect(branch.reload.receipt_logo).to be_attached

      patch admin_location_path(branch), params: { location: { remove_receipt_logo: "1" } }
      expect(branch.reload.receipt_logo).not_to be_attached
    end

    it "shows the control on the edit form with the current logo" do
      branch.receipt_logo.attach(io: File.open(png.path), filename: "b.png", content_type: "image/png")
      get edit_admin_location_path(branch)

      expect(response.body).to include('data-testid="receipt-logo-field"')
      expect(response.body).to include(I18n.t("shared.receipt_logo_field.remove"))
    end

    it "renders a multipart form so browsers send the file" do
      get edit_admin_location_path(branch)

      expect(response.body).to match(/<form[^>]*enctype="multipart\/form-data"/)
    end
  end

  describe "the public web receipt" do
    it "shows the branch logo, falling back to the company logo" do
      order = create(:order, user: owner, company: company, location: branch, status: "completed")
      get receipt_path(order.receipt_token)
      expect(response.body).not_to include("<img")

      CompanySetting.where(company: company).first_or_create!.tap do |cs|
        cs.receipt_logo.attach(io: File.open(png.path), filename: "c.png", content_type: "image/png")
        cs.save!
      end
      get receipt_path(order.receipt_token)
      expect(response.body).to include("<img")
    end
  end
end
