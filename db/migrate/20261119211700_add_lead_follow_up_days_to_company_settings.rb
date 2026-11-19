# frozen_string_literal: true

# Lead follow-up cadence (Bazzar): the first follow-up lands N days after a lead
# is created, and each logged contact pushes the next one N days out. Blank or
# 0 turns that part off for the company.
class AddLeadFollowUpDaysToCompanySettings < ActiveRecord::Migration[7.1]
  def change
    add_column :company_settings, :lead_first_follow_up_days, :integer, default: 1
    add_column :company_settings, :lead_follow_up_every_days, :integer, default: 3
  end
end
