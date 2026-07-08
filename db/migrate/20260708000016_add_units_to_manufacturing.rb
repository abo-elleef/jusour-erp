# frozen_string_literal: true

class AddUnitsToManufacturing < ActiveRecord::Migration[7.1]
  def change
    # Unit the input line quantity is expressed in (null = input ingredient's base unit).
    add_column :manufacturing_template_lines, :unit, :string
    # Unit the yield is expressed in (null = output ingredient's base unit).
    add_column :manufacturing_templates, :yield_unit, :string
  end
end
