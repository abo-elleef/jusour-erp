# frozen_string_literal: true

class AuditLogEntry < ApplicationRecord
  include Tenantable

  belongs_to :user, optional: true

  validates :action, :record_type, :record_id, presence: true

  before_update { raise ActiveRecord::ReadOnlyRecord }
  before_destroy { raise ActiveRecord::ReadOnlyRecord }

  def record
    return nil unless record_type.present? && record_id.present?

    record_type.constantize.find_by(id: record_id)
  end

  # Duck-types as an Audited::Audit so callers (e.g. audit_history_rows, the
  # shared/audit_history partial) can render either kind of audit trail the
  # same way.
  def audited_changes
    changes_snapshot
  end

  # created_at only needs overriding for a backfill (e.g. rake
  # attendance:backfill_audit_history), to log a past event at the time it
  # actually happened rather than when the backfill ran.
  def self.record!(action:, record:, user: nil, changes_snapshot: {}, ip_address: nil, created_at: Time.current)
    company = record.try(:company) || user&.company || Current.company
    create!(
      action: action,
      record_type: record.class.name,
      record_id: record.id,
      user: user,
      company: company,
      changes_snapshot: changes_snapshot,
      ip_address: ip_address,
      created_at: created_at
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
