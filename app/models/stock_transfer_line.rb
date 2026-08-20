# frozen_string_literal: true

class StockTransferLine < ApplicationRecord
  include UnitReferenced

  belongs_to :stock_transfer
  belongs_to :ingredient
  references_unit :unit, column: :unit_id
  has_many :stock_transfer_shipment_lines, dependent: :restrict_with_error

  # Requested quantity as typed in `unit`; converted to base on the way in so the
  # transfer engine only ever sees base-unit quantities.
  attr_reader :quantity_requested_input

  # This is a virtual attribute, so assigning it leaves the record "unchanged"
  # and `has_many` autosave skips the child outright — before_validation never
  # runs and the typed quantity is silently dropped. Flagging quantity_requested
  # dirty keeps the record in the autosave set. The conversion itself stays in
  # before_validation, which runs after `unit` has been assigned too, so a line
  # that changes unit and quantity together still converts against the new unit.
  def quantity_requested_input=(value)
    @quantity_requested_input = value
    quantity_requested_will_change! if value.present?
  end

  validates :ingredient_id, uniqueness: { scope: :stock_transfer_id }
  # A draft may hold an ingredient-only row whose quantity isn't typed in yet.
  # Submitting flips the parent out of draft, so this reverts to a strict
  # positive check and the placeholder rows surface as errors.
  validates :quantity_requested, numericality: { greater_than: 0 }, unless: :draft_parent?
  validates :quantity_requested, numericality: { greater_than_or_equal_to: 0 }, if: :draft_parent?
  validates :quantity_sent, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity_received, numericality: { greater_than_or_equal_to: 0 }
  validates :order_limit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :counted_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :unit_valid_for_ingredient

  before_validation :convert_requested_input

  scope :ordered, -> { order(:position, :created_at) }

  # Show a base-unit quantity in this line's (fixed) unit.
  def in_line_unit(base_quantity)
    ingredient.from_base(base_quantity.to_d, unit)
  rescue ArgumentError
    # Bad/legacy unit on the line — show the stored base quantity rather than
    # crashing transfer/stock-take show pages.
    base_quantity.to_d
  end

  # Convert a quantity typed in this line's unit back to the base unit.
  def to_base_unit(quantity)
    ingredient.to_base(quantity.to_d, unit)
  end

  def available_at_source
    il = stock_transfer.from_location.ingredient_stock(ingredient)
    il&.quantity_on_hand.to_d
  end

  def available_batches_at_source
    ingredient.stock_batches
      .where(location: stock_transfer.from_location)
      .with_stock
      .sum(:quantity_remaining).to_d
  end

  def transferable_quantity_at_source
    [available_at_source, available_batches_at_source].min
  end

  # True when source cannot cover what still needs to be sent. Used for visual
  # warnings even when restrict-to-source is turned off.
  def short_at_source?
    quantity_pending_send.positive? && transferable_quantity_at_source < quantity_pending_send
  end

  # After receipt, unrestricted sends can drive source on-hand below zero.
  # Used by the completed-transfer shortage report (independent of restrict mode).
  def source_on_hand_short?
    available_at_source.negative?
  end

  def quantity_pending_send
    [quantity_requested.to_d - quantity_sent.to_d, 0].max
  end

  def quantity_in_transit
    [quantity_sent.to_d - quantity_received.to_d, 0].max
  end

  def quantity_remaining_to_receive
    quantity_in_transit
  end

  def fulfilled?
    quantity_received.to_d >= quantity_requested.to_d
  end

  def draft_parent?
    stock_transfer&.draft?
  end

  # A draft placeholder: ingredient chosen, quantity still blank.
  def awaiting_quantity?
    quantity_requested.to_d <= 0
  end

  # Suggested request qty in the line unit: limit − counted (never negative).
  def recommended_quantity
    return if order_limit.nil? || counted_quantity.nil?

    [order_limit.to_d - counted_quantity.to_d, 0.to_d].max
  end

  private

  def convert_requested_input
    return if quantity_requested_input.blank?

    self.quantity_requested = ingredient.to_base(quantity_requested_input, unit)
  end

  def unit_valid_for_ingredient
    return if unit.blank? || ingredient.blank?
    return if ingredient.available_units.include?(unit)

    errors.add(:unit, :invalid)
  end
end
