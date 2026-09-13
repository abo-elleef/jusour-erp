# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::StockTransfers duplicate", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:manager) { create(:user, :manager, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let(:branch) { create(:location, company: company, name: "Branch A") }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, quantity_on_hand: 50.0) }
  let(:other_ingredient) { create(:ingredient, company: company, ingredient_category: category, quantity_on_hand: 50.0) }

  # Lazy, not `let!`: a bang would run before the `before` hook below, and the
  # lines' units resolve against Current.company.
  let(:source) do
    create(:stock_transfer,
      company: company,
      from_location: kitchen,
      to_location: branch,
      requested_by: owner,
      status: "completed",
      notes: "Weekly top-up",
      transferred_on: Date.current - 10.days).tap do |transfer|
        transfer.stock_transfer_lines.create!(
          ingredient: ingredient, unit: ingredient.unit,
          quantity_requested: 4, order_limit: 10, counted_quantity: 3, position: 0
        )
        transfer.stock_transfer_lines.create!(
          ingredient: other_ingredient, unit: other_ingredient.unit,
          quantity_requested: 7, position: 1
        )
      end
  end

  before { Current.company = company }

  describe "authorization" do
    it "lets an owner open the pre-filled form" do
      sign_in owner
      get duplicate_admin_inventory_stock_transfer_path(source)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(source.transfer_number)
    end

    # raise_on_missing_translations is on in test, so rendering the page in each
    # locale is what proves both en.yml and ar.yml carry the new keys.
    %i[en ar].each do |locale|
      it "renders the review banner and heading in #{locale}" do
        sign_in owner
        # `?locale=` is what actually switches the request locale (see Locale concern);
        # I18n.with_locale would be overridden by the around_action.
        get duplicate_admin_inventory_stock_transfer_path(source, locale: locale)

        expect(response.body).to include(I18n.t("inventory.stock_transfers.duplicate_title", locale: locale))
        expect(response.body).to include(I18n.t("inventory.stock_transfers.duplicate_banner_title", locale: locale))
      end
    end

    it "hides the template picker, which would discard the copied lines" do
      sign_in owner
      template = StockTransferTemplate.new(company: company, name: "Weekly", active: true)
      template.stock_transfer_template_lines.build(
        ingredient: ingredient, unit: ingredient.unit, default_quantity: 2
      )
      template.save!

      get duplicate_admin_inventory_stock_transfer_path(source)
      expect(response.body).not_to include(I18n.t("inventory.stock_transfers.form.choose_template"))

      get new_admin_inventory_stock_transfer_path
      expect(response.body).to include(I18n.t("inventory.stock_transfers.form.choose_template"))
    end

    it "denies a manager, who can otherwise manage inventory" do
      sign_in manager
      expect(manager.can?("inventory:manage")).to be(true)

      get duplicate_admin_inventory_stock_transfer_path(source)
      expect(response).not_to have_http_status(:ok)
    end

    it "hides the button on the show page from a manager" do
      sign_in manager
      get admin_inventory_stock_transfer_path(source)
      expect(response.body).not_to include(duplicate_admin_inventory_stock_transfer_path(source))

      sign_in owner
      get admin_inventory_stock_transfer_path(source)
      expect(response.body).to include(duplicate_admin_inventory_stock_transfer_path(source))
    end
  end

  describe "the copy" do
    it "saves nothing — it is only a form to review" do
      sign_in owner
      path = duplicate_admin_inventory_stock_transfer_path(source)

      expect { get path }.not_to change(StockTransfer, :count)
    end

    it "carries the locations, notes and every line over" do
      copy = source.duplicate

      expect(copy).to be_new_record
      expect(copy.from_location_id).to eq(kitchen.id)
      expect(copy.to_location_id).to eq(branch.id)
      expect(copy.notes).to eq("Weekly top-up")
      expect(copy.stock_transfer_lines.map(&:ingredient_id))
        .to eq([ingredient.id, other_ingredient.id])
      expect(copy.stock_transfer_lines.map(&:quantity_requested_input).map(&:to_d))
        .to eq([4.to_d, 7.to_d])
      expect(copy.stock_transfer_lines.map(&:unit)).to eq([ingredient.unit, other_ingredient.unit])
    end

    it "resets the date to today rather than backdating the new movement" do
      expect(source.duplicate.transferred_on).to eq(Date.current)
    end

    it "carries the par level but not the stale shelf count" do
      line = source.duplicate.stock_transfer_lines.first

      expect(line.order_limit).to eq(10)
      expect(line.counted_quantity).to be_nil
    end

    it "creates an independent transfer when the form is submitted" do
      sign_in owner
      copy = source.duplicate

      expect {
        post admin_inventory_stock_transfers_path, params: {
          stock_transfer: {
            from_location_id: copy.from_location_id,
            to_location_id: copy.to_location_id,
            transferred_on: copy.transferred_on.to_s,
            notes: copy.notes,
            stock_transfer_lines_attributes: copy.stock_transfer_lines.each_with_index.to_h { |line, i|
              [i.to_s, {
                ingredient_id: line.ingredient_id,
                quantity_requested_input: line.quantity_requested_input.to_s,
                unit: line.unit
              }]
            }
          }
        }
      }.to change(StockTransfer, :count).by(1)

      created = StockTransfer.order(:created_at).last
      expect(created.transfer_number).not_to eq(source.transfer_number)
      expect(created.status).to eq("requested")
      expect(created.stock_transfer_lines.count).to eq(2)
      expect(source.reload.status).to eq("completed")
    end
  end
end
