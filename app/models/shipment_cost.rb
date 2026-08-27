# frozen_string_literal: true

# A landed-cost line on an import shipment (freight, customs, insurance, …). Each
# is a real cash-out Expense (hits a treasury + the ledger); the amount also joins
# the shipment's cost pool for allocation across products.
class ShipmentCost < ApplicationRecord
  include MoneyInputs

  COST_TYPES = %w[freight customs insurance clearance transport other].freeze

  belongs_to :import_shipment
  belongs_to :user
  belongs_to :treasury, optional: true
  belongs_to :expense, optional: true

  monetize :amount_cents
  money_input :amount_cents

  validates :cost_type, inclusion: { in: COST_TYPES }
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :incurred_on, presence: true

  # Removing a cost line reverses its cash-out expense (restoring the treasury and
  # unwinding the ledger entry) so the shipment pool and books stay consistent.
  before_destroy :destroy_expense

  private

  def destroy_expense
    expense&.destroy
  end
end
