# frozen_string_literal: true

class RenameNotificationsTypeColumn < ActiveRecord::Migration[7.1]
  def change
    rename_column :notifications, :type, :notification_type
  end
end
