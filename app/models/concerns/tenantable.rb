# frozen_string_literal: true

module Tenantable
  extend ActiveSupport::Concern

  included do
    belongs_to :company

    default_scope -> { where(company_id: Current.company.id) if Current.company.present? }

    before_validation :assign_company

    validates :company, presence: true
  end

  class_methods do
    def unscoped_by_company
      unscoped
    end
  end

  private

  def assign_company
    self.company ||= Current.company
  end
end
