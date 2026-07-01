# frozen_string_literal: true

class PaymentMethodTreasury < ApplicationRecord
  include Tenantable

  SUPPORTED_METHODS = Payment::DIGITAL_WALLET_METHODS.freeze

  belongs_to :company
  belongs_to :treasury

  validates :payment_method, presence: true,
                             inclusion: { in: SUPPORTED_METHODS },
                             uniqueness: { scope: :company_id }
  validates :treasury_id, presence: true
end
