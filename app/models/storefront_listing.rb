# frozen_string_literal: true

# A product published on the company's storefront. The ingredient stays the
# source of truth for name, category, unit and price; the listing only adds the
# public-facing copy, photos and ordering. Phase 2+ hangs online-ordering fields
# here too, so they stay off the operational model.
class StorefrontListing < ApplicationRecord
  include Tenantable
  include StorefrontLocalized

  audited associated_with: :company

  # Letters/digits of any script, so Arabic product names get readable slugs
  # instead of collapsing to "" the way String#parameterize would.
  SLUG_FORMAT = /\A[\p{L}\p{N}]+(?:-[\p{L}\p{N}]+)*\z/
  MAX_IMAGES = 8

  IMAGE_VARIANTS = {
    thumb: { resize_to_fill: [96, 96] },
    card: { resize_to_fill: [480, 480] },
    detail: { resize_to_limit: [1200, 1200] }
  }.freeze

  INDEX_SORTABLE_COLUMNS = %w[position name category price updated_at].freeze
  INDEX_DEFAULT_SORT = "position"
  INDEX_DEFAULT_SORT_DIRECTION = "asc"

  belongs_to :ingredient

  has_many_attached :images do |attachable|
    IMAGE_VARIANTS.each do |name, transform|
      attachable.variant name, **transform, format: :jpeg, preprocessed: true
    end
  end

  before_validation :generate_slug, if: -> { slug.blank? && ingredient.present? }
  before_validation :normalize_slug

  validates :ingredient_id, uniqueness: { scope: :company_id }
  validates :slug, presence: true, uniqueness: { scope: :company_id, case_sensitive: false },
    format: { with: SLUG_FORMAT }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :ingredient_belongs_to_company
  validate :images_are_acceptable

  scope :published, -> { where(published: true) }
  # What the public site shows: published listings whose product is still active.
  scope :visible, -> { published.joins(:ingredient).where(ingredients: { active: true }) }
  scope :ordered, -> { order(featured: :desc, position: :asc, created_at: :asc) }

  # English falls back to the inventory name rather than to the Arabic title;
  # Arabic falls back to the English title, then the inventory name.
  def display_title(locale: I18n.locale)
    return title_ar.presence || title.presence || ingredient.name if locale.to_s == "ar"

    title.presence || ingredient.name
  end

  def display_description(locale: I18n.locale)
    localized(:description, locale: locale)
  end

  def price_cents
    ingredient.selling_price_cents
  end

  def unit_label
    Ingredient.unit_display_label(ingredient.unit)
  end

  # Photos in upload order. Attachment ids are UUIDs, so the association's own
  # order (by id) is random; sorted in Ruby so a preloaded list stays one query.
  def ordered_images
    images.attachments.sort_by { |attachment| [attachment.created_at || Time.current, attachment.id.to_s] }
  end

  def cover_image
    ordered_images.first
  end

  private

  def generate_slug
    base = self.class.slugify(title.presence || ingredient.name).presence || self.class.slugify(ingredient.code)
    candidate = base
    n = 2
    siblings = self.class.unscoped_by_company.where(company_id: company_id || Current.company&.id).where.not(id: id)
    while siblings.exists?(slug: candidate)
      candidate = "#{base}-#{n}"
      n += 1
    end
    self.slug = candidate
  end

  def normalize_slug
    self.slug = self.class.slugify(slug) if slug.present?
  end

  def self.slugify(text)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("")
    text.unicode_normalize(:nfkc).downcase.strip.gsub(/[^\p{L}\p{N}]+/, "-").gsub(/\A-+|-+\z/, "")
  end

  def ingredient_belongs_to_company
    return if ingredient.nil? || company_id.nil?

    errors.add(:ingredient, :invalid) if ingredient.company_id != company_id
  end

  def images_are_acceptable
    return unless attachment_changes["images"]

    errors.add(:images, :too_many, count: MAX_IMAGES) if images.size > MAX_IMAGES
    images.each do |image|
      errors.add(:images, :invalid_image_type) unless Storefront::IMAGE_CONTENT_TYPES.include?(image.blob.content_type)
      errors.add(:images, :image_too_large) if image.blob.byte_size > Storefront::MAX_IMAGE_SIZE
    end
  end
end
