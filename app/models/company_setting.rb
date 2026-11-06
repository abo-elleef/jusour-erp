# frozen_string_literal: true

class CompanySetting < ApplicationRecord
  include HasReceiptLogo

  belongs_to :company

  validates :company, presence: true

  def self.current
    return nil unless Current.company
    where(company_id: Current.company.id).first
  end

  def self.current_or_initialize
    return new unless Current.company
    where(company_id: Current.company.id).first_or_initialize(company: Current.company)
  end
end
