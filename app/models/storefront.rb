# frozen_string_literal: true

# A company's public product catalog website — one per company. Reached at
# /s/:company_slug, and at <subdomain>.<storefront_domain> once a subdomain is
# set. Phase 1 is a catalog only: visitors browse and contact the company;
# there is no cart or checkout yet.
class Storefront < ApplicationRecord
  include Tenantable
  include StorefrontLocalized

  audited associated_with: :company

  # The company story moved to the "About us" page (data copied by
  # MoveStorefrontAboutIntoAboutPage). Ignored rather than dropped so dynos
  # still running the previous release don't break mid-deploy; drop them in a
  # later release.
  self.ignored_columns += %w[about about_ar]

  # Labels that could collide with the platform's own hosts. Extend per deploy
  # with STOREFRONT_RESERVED_SUBDOMAINS (comma-separated) when the storefront
  # domain is shared with the app itself.
  RESERVED_SUBDOMAINS = %w[
    www app admin api mail smtp ftp static assets cdn staging dev test help support status blog docs
  ].freeze
  SUBDOMAIN_FORMAT = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/
  IMAGE_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze

  # Recommended upload size (width, height in px) for each image slot — matched
  # to how the public pages crop and size them (see the variants on each model).
  # Shown under every upload field via StorefrontHelper#storefront_image_hint.
  # One image serves desktop and phones: wide images are cropped to the middle
  # on small screens, so the hints ask for a centered subject.
  IMAGE_GUIDES = {
    "logo" => [400, 160],
    "banner" => [1600, 600],
    "product" => [1200, 1200],
    "category" => [1200, 900],
    "text_image" => [1200, 900],
    "promo_banner" => [1600, 500],
    "brand_logo" => [240, 120]
  }.freeze

  # Curated, Arabic-capable Google Fonts. "system" loads nothing.
  FONTS = {
    "system" => nil,
    "cairo" => "Cairo",
    "tajawal" => "Tajawal",
    "ibm_plex_sans_arabic" => "IBM Plex Sans Arabic",
    "almarai" => "Almarai"
  }.freeze
  HEADER_STYLES = %w[light dark].freeze
  # Each network's URL must point at that network, so a social button can't be
  # turned into a link to anywhere.
  SOCIAL_NETWORKS = {
    "facebook" => %w[facebook.com fb.com],
    "instagram" => %w[instagram.com],
    "tiktok" => %w[tiktok.com],
    "youtube" => %w[youtube.com youtu.be]
  }.freeze
  # Accepted for the "Open in Maps" button — Google Maps place and share links.
  MAP_HOSTS = %w[google.com maps.google.com maps.app.goo.gl goo.gl].freeze
  HEX_COLOR = /\A#[0-9a-f]{6}\z/
  # The primary color is also used as text on white (prices, links), so it has
  # to stay readable there — WCAG's 3:1 minimum for large/bold text.
  MIN_PRIMARY_CONTRAST = 3.0
  MAX_IMAGE_SIZE = 10.megabytes

  has_many :sections, -> { order(:position, :created_at) }, class_name: "StorefrontSection", dependent: :destroy
  has_many :pages, class_name: "StorefrontPage", dependent: :destroy

  has_one_attached :logo do |attachable|
    attachable.variant :header, resize_to_limit: [320, 320], preprocessed: true
  end
  has_one_attached :banner do |attachable|
    attachable.variant :hero, resize_to_limit: [1600, 600], preprocessed: true
  end

  before_validation :normalize_subdomain
  before_validation :normalize_theme

  validates :company_id, uniqueness: true
  validates :subdomain, format: { with: SUBDOMAIN_FORMAT }, allow_nil: true
  validates :subdomain, uniqueness: { case_sensitive: false }, allow_nil: true
  validate :subdomain_not_reserved
  validate :images_are_acceptable
  validates :primary_color, :accent_color, format: { with: HEX_COLOR }
  validates :font, inclusion: { in: FONTS.keys }
  validates :header_style, inclusion: { in: HEADER_STYLES }
  validate :primary_color_readable_on_white
  validate :social_urls_point_at_their_network
  validate :announcement_url_is_safe
  validate :map_url_is_google_maps

  def self.reserved_subdomains
    RESERVED_SUBDOMAINS + ENV.fetch("STOREFRONT_RESERVED_SUBDOMAINS", "").split(",").map { |s| s.strip.downcase }
  end

  def self.base_domain
    Rails.configuration.x.storefront_domain.to_s.downcase
  end

  # "acme" for "acme.saqr.store" when the storefront domain is "saqr.store";
  # nil for the bare domain, nested subdomains, reserved labels, or any other host.
  def self.subdomain_from_host(host)
    base = base_domain
    return if base.blank? || host.blank?

    host = host.downcase
    return unless host.end_with?(".#{base}")

    label = host.delete_suffix(".#{base}")
    return if label.include?(".") || reserved_subdomains.include?(label)

    label if label.match?(SUBDOMAIN_FORMAT)
  end

  # Route constraint — cheap and DB-free on purpose; an unknown subdomain still
  # routes to the storefront controllers, which answer 404.
  def self.host_match?(request)
    subdomain_from_host(request.host).present?
  end

  # Host lookup runs before any tenant is known, so it bypasses the tenant scope.
  def self.enabled_for_subdomain(subdomain)
    unscoped_by_company.joins(:company).where(enabled: true, companies: { active: true })
      .find_by("lower(storefronts.subdomain) = ?", subdomain.to_s.downcase)
  end

  # The storefront's own URL on its subdomain, or nil before one is configured.
  def subdomain_url(port: nil)
    return if subdomain.blank? || self.class.base_domain.blank?

    scheme = Rails.env.production? ? "https" : "http"
    host = "#{subdomain}.#{self.class.base_domain}"
    port.present? && ![80, 443].include?(port.to_i) ? "#{scheme}://#{host}:#{port}" : "#{scheme}://#{host}"
  end

  def phone_url
    digits = phone.to_s.gsub(/[^\d+]/, "")
    "tel:#{digits}" if digits.present?
  end

  def whatsapp_url
    digits = whatsapp_number.to_s.gsub(/\D/, "")
    "https://wa.me/#{digits}" if digits.present?
  end

  # A link admins may put on the site: a full http(s) address, or a path on
  # the storefront itself ("/?category=..."). Never javascript:, never "//host".
  def self.safe_link?(url)
    url.to_s.match?(%r{\A/(?!/)\S*\z}) || url.to_s.match?(%r{\Ahttps?://[^\s]+\z}i)
  end

  # The home page blocks to render: the saved ones, or — until someone edits
  # the home page — the default layout, which matches the original design.
  def home_sections
    return StorefrontSection.default_layout(self) unless sections.exists?

    sections.where(enabled: true).includes(image_attachment: :blob, logos_attachments: :blob).to_a
  end

  # Published info pages with content, in their fixed order — for the footer
  # and the sitemap.
  def live_pages
    pages.with_rich_text_body.with_rich_text_body_ar.in_slot_order.select(&:live?)
  end

  def self.map_link?(url)
    uri = URI.parse(url.to_s)
    host = uri.host.to_s.downcase
    %w[http https].include?(uri.scheme) && MAP_HOSTS.any? { |h| host == h || host.end_with?(".#{h}") }
  rescue URI::InvalidURIError
    false
  end

  def self.relative_luminance(hex)
    channels = hex.delete("#").scan(/../).map { |c| c.to_i(16) / 255.0 }
    r, g, b = channels.map { |c| c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
    (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  end

  def self.contrast_ratio(hex_a, hex_b)
    a, b = [relative_luminance(hex_a), relative_luminance(hex_b)].sort.reverse
    (a + 0.05) / (b + 0.05)
  end

  # White or near-black, whichever reads better on `hex` — so a button's text
  # is legible whatever brand color the company picks.
  def self.text_color_on(hex)
    contrast_ratio(hex, "#ffffff") >= contrast_ratio(hex, "#111827") ? "#ffffff" : "#111827"
  end

  def font_family
    FONTS[font]
  end

  def google_fonts_url
    return if font_family.nil?

    "https://fonts.googleapis.com/css2?family=#{font_family.tr(' ', '+')}:wght@400;500;600;700&display=swap"
  end

  def social_links
    SOCIAL_NETWORKS.keys.filter_map do |network|
      url = public_send(:"#{network}_url")
      [network, url] if url.present?
    end
  end

  def announcement_visible?
    announcement_enabled? && localized(:announcement_text).present?
  end

  def contact_present?
    phone.present? || whatsapp_number.present? || email.present? || address.present? || map_url.present?
  end

  private

  def normalize_subdomain
    self.subdomain = subdomain.to_s.strip.downcase.presence
  end

  def normalize_theme
    self.primary_color = primary_color.to_s.strip.downcase
    self.accent_color = accent_color.to_s.strip.downcase
    self.announcement_url = announcement_url.to_s.strip
    self.map_url = map_url.to_s.strip
    SOCIAL_NETWORKS.each_key do |network|
      attribute = :"#{network}_url"
      url = public_send(attribute).to_s.strip
      # "instagram.com/curelix" is how people paste it — assume https.
      url = "https://#{url}" if url.present? && !url.match?(%r{\Ahttps?://}i)
      public_send(:"#{attribute}=", url)
    end
  end

  def primary_color_readable_on_white
    return unless primary_color.to_s.match?(HEX_COLOR)

    errors.add(:primary_color, :too_light) if self.class.contrast_ratio(primary_color, "#ffffff") < MIN_PRIMARY_CONTRAST
  end

  def social_urls_point_at_their_network
    SOCIAL_NETWORKS.each do |network, hosts|
      url = public_send(:"#{network}_url")
      next if url.blank?

      host = URI.parse(url).host.to_s.downcase rescue ""
      ok = url.match?(%r{\Ahttps?://}i) && hosts.any? { |h| host == h || host.end_with?(".#{h}") }
      errors.add(:"#{network}_url", :wrong_network) unless ok
    end
  end

  # A full http(s) link, or a path on the storefront itself ("/?category=...").
  def announcement_url_is_safe
    return if announcement_url.blank? || self.class.safe_link?(announcement_url)

    errors.add(:announcement_url, :invalid)
  end

  def map_url_is_google_maps
    errors.add(:map_url, :not_google_maps) if map_url.present? && !self.class.map_link?(map_url)
  end

  def subdomain_not_reserved
    errors.add(:subdomain, :exclusion) if subdomain.present? && self.class.reserved_subdomains.include?(subdomain)
  end

  def images_are_acceptable
    { logo: logo, banner: banner }.each do |name, attachment|
      next unless attachment_changes[name.to_s] && attachment.attached?

      errors.add(name, :invalid_image_type) unless IMAGE_CONTENT_TYPES.include?(attachment.blob.content_type)
      errors.add(name, :image_too_large) if attachment.blob.byte_size > MAX_IMAGE_SIZE
    end
  end
end
