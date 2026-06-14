# frozen_string_literal: true

class PrinterMenuItem < ApplicationRecord
  belongs_to :printer
  belongs_to :menu_item

  validates :menu_item_id, uniqueness: { scope: :printer_id }
end
