# frozen_string_literal: true

# What a customer ticket is about (product quality, delivery problem, ...).
# Editable per company on Settings; an inactive category stays on its old
# tickets but is no longer offered for new ones. default_handler is who gets
# a new ticket in this category when the opener picks nobody.
class TicketCategory < ApplicationRecord
  include Tenantable

  # Keep in step with db/migrate/*_seed_ticket_categories.rb.
  DEFAULTS = [
    { key: "product_quality", name: "Product quality", name_ar: "جودة المنتج" },
    { key: "wrong_or_missing_item", name: "Wrong or missing item", name_ar: "صنف خاطئ أو ناقص" },
    { key: "delivery_problem", name: "Delivery problem", name_ar: "مشكلة في التوصيل" },
    { key: "price_or_billing", name: "Price or billing", name_ar: "السعر أو الفاتورة" },
    { key: "other", name: "Other", name_ar: "أخرى" }
  ].freeze

  belongs_to :default_handler, class_name: "User", optional: true
  has_many :tickets, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :company_id, case_sensitive: false }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  def self.seed_defaults!(company)
    DEFAULTS.each_with_index do |attrs, position|
      next if unscoped.exists?(company_id: company.id, key: attrs[:key])

      unscoped.create!(attrs.merge(company: company, position: position))
    end
  end

  def display_name(locale = I18n.locale)
    locale.to_s == "ar" && name_ar.present? ? name_ar : name
  end

  def deletable?
    !tickets.exists?
  end
end
