# frozen_string_literal: true

class Category < ApplicationRecord
  include Tenantable

  has_many :menu_items, dependent: :destroy

  before_validation :assign_code, on: :create
  after_update :recode_menu_items, if: :saved_change_to_code?

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :code, presence: true, uniqueness: { scope: :company_id, case_sensitive: false },
    format: { with: /\A[A-Za-z0-9]+\z/, message: :alphanumeric_only }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  # A short default code derived from the name (first alphanumerics), deduped
  # within the company. Used as a prefix for this category's menu item codes.
  def self.generate_code(name, company_id)
    base = name.to_s.upcase.gsub(/[^A-Z0-9]/, "")[0, 4].presence || "CAT"
    candidate = base
    n = 1
    while unscoped_by_company.where(company_id: company_id).where("UPPER(code) = ?", candidate.upcase).exists?
      n += 1
      candidate = "#{base}#{n}"
    end
    candidate
  end

  private

  def assign_code
    self.code = self.class.generate_code(name, company_id) if code.blank?
  end

  # When the category code changes, swap the prefix on this category's items
  # whose code follows the "<old_code>-…" shape (the auto-generated ones), so
  # "BURG-001" becomes "BEEF-001". Items with unrelated custom codes are left
  # alone. Runs inside the update's transaction, so any clash rolls it back.
  def recode_menu_items
    old_code, new_code = saved_change_to_code
    return if old_code.blank? || new_code.blank?

    quoted_new = self.class.connection.quote(new_code)
    menu_items.where("code LIKE ?", "#{old_code}-%")
      .update_all(Arel.sql("code = #{quoted_new} || SUBSTRING(code FROM #{old_code.length + 1})"))
  end
end
