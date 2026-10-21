# frozen_string_literal: true

# The public face of an inventory category on the storefront: a photo plus
# display names and descriptions in English and Arabic. Rows are optional and
# created the first time someone edits a category from the admin; without one
# the category shows under its inventory name.
class StorefrontCategory < ApplicationRecord
  include Tenantable
  include StorefrontLocalized

  audited associated_with: :company

  belongs_to :ingredient_category

  has_one_attached :image do |attachable|
    attachable.variant :tile, resize_to_fill: [480, 360], format: :jpeg, preprocessed: true
    attachable.variant :header, resize_to_fill: [1200, 400], format: :jpeg, preprocessed: true
  end

  validates :ingredient_category_id, uniqueness: { scope: :company_id }
  validate :ingredient_category_belongs_to_company
  validate :image_is_acceptable

  # The display name for a category, with or without its storefront row.
  def self.display_name(category, storefront_category, locale: I18n.locale)
    return category.name if storefront_category.nil?

    storefront_category.display_title(locale: locale)
  end

  def display_title(locale: I18n.locale)
    return title_ar.presence || title.presence || ingredient_category.name if locale.to_s == "ar"

    title.presence || ingredient_category.name
  end

  def display_description(locale: I18n.locale)
    localized(:description, locale: locale)
  end

  private

  def ingredient_category_belongs_to_company
    return if ingredient_category.nil? || company_id.nil?

    errors.add(:ingredient_category, :invalid) if ingredient_category.company_id != company_id
  end

  def image_is_acceptable
    return unless attachment_changes["image"] && image.attached?

    errors.add(:image, :invalid_image_type) unless Storefront::IMAGE_CONTENT_TYPES.include?(image.blob.content_type)
    errors.add(:image, :image_too_large) if image.blob.byte_size > Storefront::MAX_IMAGE_SIZE
  end
end
