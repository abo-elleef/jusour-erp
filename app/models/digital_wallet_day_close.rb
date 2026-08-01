# frozen_string_literal: true

class DigitalWalletDayClose < ApplicationRecord
  include Tenantable

  belongs_to :company
  belongs_to :recorded_by, class_name: "User"
  belongs_to :location, optional: true

  monetize :instapay_statement_cents
  monetize :vodafone_cash_statement_cents

  validates :business_date, presence: true, uniqueness: { scope: %i[company_id location_id] }
  validates :instapay_statement_cents, :vodafone_cash_statement_cents,
            numericality: { greater_than_or_equal_to: 0 }

  def statement_cents_for(method)
    case method.to_s
    when "instapay" then instapay_statement_cents
    when "vodafone_cash" then vodafone_cash_statement_cents
    else 0
    end
  end
end
