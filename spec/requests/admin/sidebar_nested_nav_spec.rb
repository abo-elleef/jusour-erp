# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin sidebar nested module nav", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }

  before { sign_in owner }

  describe "GET admin root" do
    it "renders Accounting and Inventory as nested accordions with leaf links" do
      get admin_root_path
      expect(response).to have_http_status(:ok)

      expect(response.body).to include('data-controller="nested-nav"')
      expect(response.body).to include('data-nested-nav-key-value="accounting"')
      expect(response.body).to include('data-nested-nav-key-value="inventory"')

      expect(response.body).to include(admin_accounting_attendance_path)
      expect(response.body).to include(admin_accounting_expenses_path)
      expect(response.body).to include(admin_accounting_treasuries_path)
      expect(response.body).to include(admin_inventory_ingredients_path)
      expect(response.body).to include(admin_inventory_vendor_invoices_path)

      # Module rows are buttons (no navigation), not links to the old landings.
      expect(response.body).to include('data-nested-nav-module-button')
      expect(response.body).not_to match(
        %r{<a[^>]+href="#{Regexp.escape(admin_accounting_treasuries_path)}"[^>]*>\s*(?:<svg[\s\S]*?</svg>)?\s*<span[^>]*>\s*#{Regexp.escape(I18n.t("nav.accounting"))}}
      )
      expect(response.body).not_to match(
        %r{<a[^>]+href="#{Regexp.escape(admin_inventory_vendor_invoices_path)}"[^>]*>\s*(?:<svg[\s\S]*?</svg>)?\s*<span[^>]*>\s*#{Regexp.escape(I18n.t("nav.inventory"))}}
      )
    end
  end

  describe "permission filtering" do
    it "shows Attendance for a sub-manager with attendance:log" do
      staff = create(:user, company: company, role: "sub_manager")
      sign_in staff

      get admin_root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(admin_accounting_attendance_path)
      expect(response.body).not_to include(admin_accounting_treasuries_path)
    end
  end

  describe "active expansion on accounting pages" do
    it "marks Accounting open when viewing attendance" do
      get admin_accounting_attendance_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-nested-nav-key-value="accounting"')
      expect(response.body).to include('data-nested-nav-open-value="true"')
      # No per-group open-state: app/views/admin/_flat_module_nav.html.erb
      # deliberately flattened Accounting's sub-groups into one list (its own
      # comment: "whose groups have been merged on purpose") — there is no
      # "transactions" sub-group left to mark open.
    end
  end
end
