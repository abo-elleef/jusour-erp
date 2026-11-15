# frozen_string_literal: true

module Sales
  # One cell of the owner's role × invoice-stage grid: whether the role's
  # members see invoices at this stage and whether they're notified when an
  # invoice enters it. See Sales::StageVisibility for how it's applied.
  class StageAccess < ApplicationRecord
    self.table_name = "sales_stage_accesses"

    include Tenantable

    belongs_to :role

    validates :stage, inclusion: { in: CustomerInvoice::STAGES }, uniqueness: { scope: :role_id }
  end
end
