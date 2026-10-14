# frozen_string_literal: true

class TreasuryTransaction < ApplicationRecord
  include Tenantable

  # fixed_asset_purchase / fixed_asset_payment are investing flows, not operating —
  # buying a machine is a balance-sheet swap, not an expense. Kept distinct from
  # `expense` so the cash flow statement can classify them correctly.
  # `cash_sale` is a sale settled at the point of sale — money straight into the
  # treasury, never a receivable. Distinct from `ar_payment`, which settles a debt
  # that already existed.
  KINDS = %w[expense income drawer_open drawer_reconcile drawer_deposit adjustment transfer ap_invoice ap_payment ap_credit_note ar_invoice ar_payment ar_credit_note cash_sale payroll_advance payroll_salary staff_meal online_payment journal_entry fixed_asset_purchase fixed_asset_payment
                voucher_receipt voucher_payment shipping_company_charge shipping_company_payment shipping_company_fee_payable].freeze

  belongs_to :treasury
  belongs_to :user
  belongs_to :source_record, polymorphic: true, optional: true

  monetize :amount_cents
  monetize :balance_after_cents

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :description, :occurred_on, :amount_cents, presence: true
  validates :amount_cents, numericality: { other_than: 0 }

  scope :recent, -> { order(occurred_on: :desc, created_at: :desc) }
  scope :on_date_range, ->(start_date, end_date) { where(occurred_on: start_date..end_date) }

  def inflow?
    amount_cents.positive?
  end

  def outflow?
    amount_cents.negative?
  end
end
