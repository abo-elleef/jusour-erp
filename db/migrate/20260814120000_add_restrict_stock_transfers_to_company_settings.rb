# frozen_string_literal: true

class AddRestrictStockTransfersToCompanySettings < ActiveRecord::Migration[7.1]
  def change
    add_column :company_settings, :restrict_stock_transfers_to_source, :boolean,
      default: true, null: false
  end
end
