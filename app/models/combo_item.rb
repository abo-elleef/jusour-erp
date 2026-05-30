# frozen_string_literal: true

class ComboItem < ApplicationRecord
  belongs_to :combo
  belongs_to :menu_item

  validates :quantity, numericality: { greater_than: 0, only_integer: true }
end
