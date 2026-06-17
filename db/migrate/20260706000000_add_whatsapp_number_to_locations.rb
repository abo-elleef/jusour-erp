# frozen_string_literal: true

class AddWhatsappNumberToLocations < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :whatsapp_number, :string
  end
end
