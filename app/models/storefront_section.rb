# frozen_string_literal: true

# One block of the storefront home page. The block types are fixed and each
# one's options are declared in TYPES — assign_settings keeps only those keys,
# casts them, and the templates in public/storefronts/sections render them.
# Admins choose, order and fill blocks; they never supply markup.
class StorefrontSection < ApplicationRecord
  include Tenantable

  audited associated_with: :company

  MAX_SECTIONS = 20
  MAX_LOGOS = 12
  LIMITS = [4, 8, 12].freeze
  TEXT_LIMIT = 160
  LONG_TEXT_LIMIT = 3_000

  # Field kinds:
  #   text / long_text — English in `name`, Arabic in `name_ar`
  #   boolean, limit (one of LIMITS), category (an inventory category id),
  #   link (Storefront.safe_link?), choice (options:)
  TYPES = {
    "hero" => [
      { name: "headline", kind: :text },
      { name: "subheadline", kind: :text },
      { name: "show_contact_buttons", kind: :boolean, default: true }
    ],
    "categories" => [{ name: "title", kind: :text }],
    "featured_products" => [{ name: "title", kind: :text }, { name: "limit", kind: :limit, default: 8 }],
    "category_products" => [
      { name: "category_id", kind: :category },
      { name: "title", kind: :text },
      { name: "limit", kind: :limit, default: 4 }
    ],
    "all_products" => [{ name: "title", kind: :text }],
    "text_image" => [
      { name: "title", kind: :text },
      { name: "body", kind: :long_text },
      { name: "image_position", kind: :choice, options: %w[end start], default: "end" }
    ],
    "promo_banner" => [
      { name: "title", kind: :text },
      { name: "subtitle", kind: :text },
      { name: "button_label", kind: :text },
      { name: "link", kind: :link }
    ],
    "brand_logos" => [{ name: "title", kind: :text }],
    # A teaser of the "About us" page with a "Read more" link — the story
    # itself is written once, on that page.
    "about" => [{ name: "title", kind: :text }]
  }.freeze

  IMAGE_TYPES = %w[text_image promo_banner].freeze
  LOGO_TYPES = %w[brand_logos].freeze
  # The paginated product grid can appear once.
  SINGLETON_TYPES = %w[all_products].freeze
  DEFAULT_LAYOUT = %w[hero categories featured_products all_products].freeze

  belongs_to :storefront

  has_one_attached :image do |attachable|
    attachable.variant :wide, resize_to_limit: [1600, 700], format: :jpeg, preprocessed: true
    attachable.variant :half, resize_to_limit: [900, 900], format: :jpeg, preprocessed: true
  end
  has_many_attached :logos do |attachable|
    attachable.variant :logo, resize_to_limit: [240, 120], preprocessed: true
  end

  validates :section_type, inclusion: { in: TYPES.keys }
  validate :within_section_limit, on: :create
  validate :singleton_not_duplicated
  validate :settings_are_valid
  validate :images_are_acceptable

  before_validation :assign_storefront_company

  def self.default_layout(storefront)
    DEFAULT_LAYOUT.each_with_index.map do |type, index|
      new(storefront: storefront, company_id: storefront.company_id, section_type: type, position: index, enabled: true)
    end
  end

  # Persists the default layout so the admin has rows to edit. No-op once any exist.
  def self.seed_defaults!(storefront)
    return if storefront.sections.exists?

    transaction { default_layout(storefront).each(&:save!) }
  end

  def fields
    TYPES.fetch(section_type, [])
  end

  def image?
    IMAGE_TYPES.include?(section_type)
  end

  def logos?
    LOGO_TYPES.include?(section_type)
  end

  def setting(name)
    field = fields.find { |f| f[:name] == name.to_s }
    value = settings.to_h[name.to_s]
    value.nil? ? field&.dig(:default) : value
  end

  # A text setting in the visitor's language, falling back to the other one.
  def text(name, locale: I18n.locale)
    english = settings.to_h[name.to_s].to_s
    arabic = settings.to_h["#{name}_ar"].to_s
    locale.to_s == "ar" ? arabic.presence || english : english.presence || arabic
  end

  def ingredient_category
    id = setting(:category_id)
    IngredientCategory.find_by(id: id) if id.present?
  end

  # Keeps only the keys this block declares, cast to their kind. Unknown keys
  # from the form are dropped, so the JSON can't grow anything free-form.
  def assign_settings(raw)
    raw = raw.to_h.stringify_keys
    cleaned = {}
    fields.each do |field|
      name = field[:name]
      case field[:kind]
      when :text, :long_text
        limit = field[:kind] == :text ? TEXT_LIMIT : LONG_TEXT_LIMIT
        [name, "#{name}_ar"].each do |key|
          cleaned[key] = raw[key].to_s.strip.first(limit) if raw.key?(key)
        end
      when :boolean
        cleaned[name] = ActiveModel::Type::Boolean.new.cast(raw[name]) || false if raw.key?(name)
      when :limit
        cleaned[name] = raw[name].to_i if raw.key?(name)
      when :category, :link, :choice
        cleaned[name] = raw[name].to_s.strip if raw.key?(name)
      end
    end
    self.settings = settings.to_h.merge(cleaned)
  end

  # Upload order, same reasoning as StorefrontListing#ordered_images.
  def ordered_logos
    logos.attachments.sort_by { |attachment| [attachment.created_at || Time.current, attachment.id.to_s] }
  end

  private

  def assign_storefront_company
    self.company_id ||= storefront&.company_id
  end

  def within_section_limit
    return if storefront.nil?

    errors.add(:base, :too_many_sections, count: MAX_SECTIONS) if storefront.sections.count >= MAX_SECTIONS
  end

  def singleton_not_duplicated
    return unless SINGLETON_TYPES.include?(section_type) && storefront

    others = storefront.sections.where(section_type: section_type).where.not(id: id)
    errors.add(:section_type, :only_one) if others.exists?
  end

  def settings_are_valid
    fields.each do |field|
      value = setting(field[:name])
      case field[:kind]
      when :limit
        errors.add(:base, :invalid_limit) unless LIMITS.include?(value.to_i)
      when :choice
        errors.add(:base, :invalid_choice) unless field[:options].include?(value.to_s)
      when :link
        errors.add(:base, :invalid_link) if value.present? && !Storefront.safe_link?(value)
      when :category
        category = IngredientCategory.unscoped_by_company.find_by(id: value) if value.present?
        errors.add(:base, :category_required) if category.nil? || category.company_id != company_id
      end
    end
  end

  def images_are_acceptable
    if attachment_changes["image"] && image.attached?
      errors.add(:image, :invalid_image_type) unless Storefront::IMAGE_CONTENT_TYPES.include?(image.blob.content_type)
      errors.add(:image, :image_too_large) if image.blob.byte_size > Storefront::MAX_IMAGE_SIZE
    end
    return unless attachment_changes["logos"]

    errors.add(:logos, :too_many, count: MAX_LOGOS) if logos.size > MAX_LOGOS
    logos.each do |logo|
      errors.add(:logos, :invalid_image_type) unless Storefront::IMAGE_CONTENT_TYPES.include?(logo.blob.content_type)
      errors.add(:logos, :image_too_large) if logo.blob.byte_size > Storefront::MAX_IMAGE_SIZE
    end
  end
end
