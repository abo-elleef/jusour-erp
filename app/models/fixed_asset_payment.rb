# frozen_string_literal: true

# One installment against a fixed asset bought on credit. Cash leaves the paying
# treasury here, not at acquisition.
class FixedAssetPayment < ApplicationRecord
  include Tenantable
  include MoneyInputs

  belongs_to :fixed_asset
  belongs_to :user
  belongs_to :treasury

  monetize :amount_cents
  money_input :amount_cents

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :payment_date, presence: true
  validate :within_balance_due

  scope :ordered, -> { order(:payment_date, :created_at) }

  private

  # An installment must not take the asset past its purchase price — otherwise the
  # payable would go negative and the ledger would stop tying to the asset.
  def within_balance_due
    return if fixed_asset.blank? || amount_cents.to_i <= 0

    already_paid = fixed_asset.fixed_asset_payments.where.not(id: id).sum(:amount_cents)
    remaining = fixed_asset.purchase_price_cents.to_i - already_paid
    return if amount_cents.to_i <= remaining

    errors.add(:amount_cents, :greater_than,
      count: I18n.t("accounting.fixed_assets.errors.exceeds_balance",
                    remaining: ActiveSupport::NumberHelper.number_to_rounded(remaining / 100.0, precision: 2)))
  end
end
