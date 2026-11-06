# frozen_string_literal: true

require "rails_helper"

# Financial reports put a small copy icon next to each figure. What it copies
# must be the plain number, so it pastes into Google Sheets or a calculator.
RSpec.describe "Copy-amount buttons on accounting reports", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:owner) { create(:user, :owner, company: Current.company) }

  before { sign_in owner }

  describe "ApplicationHelper#copy_amount_button" do
    let(:view) { ApplicationController.new.helpers }

    it "copies a plain two-decimal number with no separators or currency" do
      html = view.copy_amount_button(123_456_78)
      expect(html).to include('data-copy-number-text-value="123456.78"')
    end

    it "keeps the minus sign for negatives" do
      expect(view.copy_amount_button(-250_00)).to include('data-copy-number-text-value="-250.00"')
    end

    it "treats nil as zero" do
      expect(view.copy_amount_button(nil)).to include('data-copy-number-text-value="0.00"')
    end
  end

  %i[profit_loss balance_sheet cash_flow profit_vs_cash].each do |report|
    it "renders on #{report}" do
      get public_send("#{report}_admin_accounting_financial_statements_path")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="copy-number"')
    end
  end
end
