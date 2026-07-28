# frozen_string_literal: true

# A named bundle of permissions, scoped per company so owners can customise or
# add their own roles. `built_in` roles (owner, manager, …, sub_manager,
# super_manager) are seeded per company; owners may edit their permissions but
# the app relies on their `key` existing.
class Role < ApplicationRecord
  include Tenantable

  has_many :users, foreign_key: :role_id, inverse_of: :assigned_role, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :company_id, case_sensitive: false }
  validate :permissions_are_known

  before_destroy :prevent_builtin_destroy

  scope :ordered, -> { order(built_in: :desc, name: :asc) }

  def can?(permission)
    permission_keys.include?(permission.to_s)
  end

  def permission_keys
    Array(permissions)
  end

  # Normalises a submitted list (checkboxes) to the known catalog, dropping blanks
  # and anything unknown.
  def permissions=(value)
    super(Array(value).map(&:to_s).reject(&:blank?) & Permission::KEYS)
  end

  private

  def permissions_are_known
    unknown = permission_keys - Permission::KEYS
    return if unknown.empty?

    errors.add(:permissions, "unknown keys: #{unknown.join(', ')}")
  end

  def prevent_builtin_destroy
    return unless built_in?

    errors.add(:base, I18n.t("roles.cannot_delete_builtin"))
    throw :abort
  end
end
