# frozen_string_literal: true

class IngredientCategory < ApplicationRecord
  include Tenantable

  audited associated_with: :company

  has_many :ingredients, dependent: :restrict_with_error

  # The code is derived from the name and kept in sync (name-driven): renaming
  # the category re-derives the code and cascades it into every ingredient code.
  before_validation :sync_code
  after_update :recode_ingredients, if: :saved_change_to_code?

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :code, presence: true, uniqueness: { scope: :company_id, case_sensitive: false }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  # A code derived from the name: Unicode letters/digits only (so Arabic names
  # stay meaningful), deduped within the company. Excludes `except_id` (self).
  def self.generate_code(name, company_id, except_id: nil)
    base = name.to_s.dup.force_encoding("UTF-8").strip.upcase.gsub(/[^\p{Alnum}]+/, "").presence || "CAT"
    rel = unscoped_by_company.where(company_id: company_id)
    rel = rel.where.not(id: except_id) if except_id
    candidate = base
    n = 1
    while rel.where("UPPER(code) = ?", candidate.upcase).exists?
      n += 1
      candidate = "#{base}#{n}"
    end
    candidate
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name active position]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  private

  def sync_code
    return if name.blank?
    return unless code.blank? || name_changed?

    self.code = self.class.generate_code(name, company_id, except_id: id)
  end

  # Swap the prefix on this category's ingredients whose code is "<old>-…" (the
  # auto-generated ones) so they follow the renamed category. Custom codes that
  # don't match are left alone. Runs inside the update's transaction.
  def recode_ingredients
    old_code, new_code = saved_change_to_code
    return if old_code.blank? || new_code.blank?

    quoted_new = self.class.connection.quote(new_code)
    ingredients.where("code LIKE ?", "#{old_code}-%")
      .update_all(Arel.sql("code = #{quoted_new} || SUBSTRING(code FROM #{old_code.length + 1})"))
  end
end
