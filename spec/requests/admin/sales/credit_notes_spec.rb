# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Sales::CreditNotes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg") }
  let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "commercial") }

  before do
    Current.company = company
    sign_in owner
  end

  def draft_credit_note
    cn = CreditNote.new(company: company, customer: customer, user: owner, location: location,
      credit_note_date: Date.current, restock: false)
    cn.credit_note_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit, unit_price_cents: 10_000)
    cn.save!
    cn
  end

  describe "PATCH /admin/sales/credit_notes/:id/void" do
    it "voids a draft without touching the customer balance" do
      cn = draft_credit_note

      patch void_admin_sales_credit_note_path(cn)

      expect(cn.reload.status).to eq("void")
      expect(response).to redirect_to(admin_sales_credit_notes_path)
    end

    it "refuses to void a confirmed credit note" do
      cn = draft_credit_note
      Sales::ConfirmCreditNoteService.new(cn, owner).call

      patch void_admin_sales_credit_note_path(cn)

      expect(cn.reload.status).to eq("confirmed")
      expect(response).to redirect_to(admin_sales_credit_note_path(cn))
      expect(flash[:alert]).to eq(I18n.t("sales.credit_notes.flash.cannot_void"))
    end
  end
end
