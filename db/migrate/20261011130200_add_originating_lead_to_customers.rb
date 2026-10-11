# frozen_string_literal: true

class AddOriginatingLeadToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_reference :customers, :originating_lead, type: :uuid, null: true, index: true
  end
end
