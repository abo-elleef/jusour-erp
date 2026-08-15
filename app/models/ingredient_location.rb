# frozen_string_literal: true

class IngredientLocation < ApplicationRecord
  belongs_to :ingredient
  belongs_to :location

  validates :ingredient_id, uniqueness: { scope: :location_id }
  validates :quantity_on_hand, numericality: true
  validates :reorder_threshold, numericality: { greater_than_or_equal_to: 0 }
  validates :max_quantity, numericality: { greater_than_or_equal_to: 0 }

  # The ingredient's global on-hand is always the sum of its locations. Roll it
  # up whenever a location's quantity changes so the two never drift.
  after_save :sync_ingredient_on_hand, if: :saved_change_to_quantity_on_hand?
  after_destroy :sync_ingredient_on_hand

  scope :low_stock, -> { where("ingredient_locations.quantity_on_hand <= ingredient_locations.reorder_threshold AND ingredient_locations.reorder_threshold > 0") }
  scope :out_of_stock, -> { where("ingredient_locations.quantity_on_hand <= 0") }

  def low_stock?
    quantity_on_hand <= reorder_threshold && !reorder_threshold.zero?
  end

  def out_of_stock?
    quantity_on_hand <= 0
  end

  def stock_status
    return :out if out_of_stock?
    return :low if low_stock?

    :ok
  end

  private

  # update_column: skips validations/callbacks (no recursion into ingredient
  # validations on a stock roll-up).
  def sync_ingredient_on_hand
    ingredient.update_column(:quantity_on_hand, ingredient.ingredient_locations.sum(:quantity_on_hand))
  end
end
