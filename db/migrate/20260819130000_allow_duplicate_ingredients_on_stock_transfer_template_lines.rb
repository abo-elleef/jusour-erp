# frozen_string_literal: true

class AllowDuplicateIngredientsOnStockTransferTemplateLines < ActiveRecord::Migration[7.1]
  def change
    remove_index :stock_transfer_template_lines,
      name: "index_st_template_lines_on_template_and_ingredient"

    add_index :stock_transfer_template_lines,
      %i[stock_transfer_template_id ingredient_id],
      name: "index_st_template_lines_on_template_and_ingredient"
  end
end
