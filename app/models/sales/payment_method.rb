# frozen_string_literal: true

module Sales
  # A company-configured way to take an online payment on a customer invoice
  # (InstaPay, a bank transfer, a particular mobile wallet, a card machine, ...)
  # and where that money lands. requires_approval: transfers and wallets wait
  # for someone with sales:confirm_payments to check them; a method without it
  # (the card machine at the counter) settles on confirm, like cash. Deliberately separate from PaymentMethodTreasury, which
  # is shared POS day-close infrastructure this module must not touch — see
  # [[project_distribution_pnl_reporting]] discussion on scope.
  class PaymentMethod < ApplicationRecord
    self.table_name = "sales_payment_methods"

    include Tenantable

    belongs_to :treasury
    has_many :customer_invoices, dependent: :restrict_with_error
    # Who approves payments by this method; empty = anyone with
    # sales:confirm_payments (see Sales::PaymentApproval).
    has_many :approver_links, class_name: "Sales::PaymentMethodApprover",
      foreign_key: :sales_payment_method_id, inverse_of: :sales_payment_method, dependent: :destroy
    has_many :approvers, through: :approver_links, source: :user

    INDEX_SORTABLE_COLUMNS = %w[name active requires_approval created_at].freeze
    INDEX_DEFAULT_SORT = "name"
    INDEX_DEFAULT_SORT_DIRECTION = "asc"

    validates :name, presence: true, uniqueness: { scope: :company_id }
    validates :treasury_id, presence: true

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:name) }

    def self.ransackable_attributes(_auth_object = nil)
      %w[name active requires_approval created_at]
    end

    # Used once a method has settled real invoices — deleting it would orphan
    # their sales_payment_method_id. Mark it inactive instead.
    def deletable?
      !customer_invoices.exists?
    end
  end
end
