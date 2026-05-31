# frozen_string_literal: true

class AuditLogEntry < ApplicationRecord
  belongs_to :user, optional: true

  validates :action, :record_type, :record_id, presence: true

  before_update { raise ActiveRecord::ReadOnlyRecord }
  before_destroy { raise ActiveRecord::ReadOnlyRecord }

  def record
    return nil unless record_type.present? && record_id.present?

    record_type.constantize.find_by(id: record_id)
  end

  def self.record!(action:, record:, user: nil, changes_snapshot: {}, ip_address: nil)
    create!(
      action: action,
      record_type: record.class.name,
      record_id: record.id,
      user: user,
      changes_snapshot: changes_snapshot,
      ip_address: ip_address
    )
  end

  ransacker :logged_on, type: :date do
    Arel.sql("DATE(#{table_name}.created_at)")
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[action record_type record_id created_at user_id logged_on]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[user]
  end
end
