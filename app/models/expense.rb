# frozen_string_literal: true

class Expense < ApplicationRecord
  include Tenantable

  RECURRENCES = %w[one_time daily weekly monthly annually].freeze

  belongs_to :expense_category
  belongs_to :user
  belongs_to :treasury, optional: true
  belongs_to :source_record, polymorphic: true, optional: true

  has_one_attached :receipt_image

  has_one :vendor_invoice_payment, as: :source_record

  monetize :amount_cents

  validates :description, :expense_date, :amount_cents, presence: true
  validates :recurrence, inclusion: { in: RECURRENCES }
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :treasury, presence: true, unless: :is_auto_generated?

  scope :manual, -> { where(is_auto_generated: false) }
  scope :auto_generated, -> { where(is_auto_generated: true) }
  scope :on_date_range, ->(start_date, end_date) {
    where(expense_date: start_date..end_date)
  }

  after_commit :sync_treasury_ledger, on: %i[create update]
  after_destroy :remove_treasury_ledger

  def self.ransackable_attributes(_auth_object = nil)
    %w[description expense_date amount_cents is_auto_generated expense_category_id treasury_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[expense_category user treasury]
  end

  private

  def sync_treasury_ledger
    Accounting::TreasuryLedgerService.sync_expense!(self)
  end

  def remove_treasury_ledger
    Accounting::TreasuryLedgerService.remove_source!(self)
  end
end
