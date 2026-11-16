# frozen_string_literal: true

class ModifierGroup < ApplicationRecord
  include Tenantable

  has_many :modifiers, -> { order(:position, :name) }, dependent: :destroy
  has_many :menu_item_modifier_groups, dependent: :destroy
  has_many :menu_items, through: :menu_item_modifier_groups

  validates :name, presence: true
  validates :max_selections, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # The cap only means something for a multi-select group; a single-choice
  # group is always "pick one".
  before_validation { self.max_selections = nil unless multi_select }

  scope :ordered, -> { order(:position, :name) }

  accepts_nested_attributes_for :modifiers, allow_destroy: true,
    reject_if: proc { |attrs| attrs["name"].blank? }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name required multi_select max_selections position]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[modifiers menu_items]
  end
end
