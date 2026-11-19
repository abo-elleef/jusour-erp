# frozen_string_literal: true

# How each kind of notification arrives live (alert / popup / quiet), keyed by
# message_key. Only the owner's overrides are stored; see Notifications::Levels.
class AddNotificationLevelsToCompanySettings < ActiveRecord::Migration[7.1]
  def change
    add_column :company_settings, :notification_levels, :jsonb, default: {}, null: false
  end
end
