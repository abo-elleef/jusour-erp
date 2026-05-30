# frozen_string_literal: true

class ModifierGroup < ApplicationRecord
  belongs_to :menu_item
  has_many :modifiers, dependent: :destroy

  validates :name, presence: true

  accepts_nested_attributes_for :modifiers, allow_destroy: true,
    reject_if: proc { |attrs| attrs["name"].blank? }
end
