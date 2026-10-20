# frozen_string_literal: true

# A company's public product catalog website — one per company. Reached at
# /s/:company_slug, and at <subdomain>.<storefront_domain> once a subdomain is
# set. Phase 1 is a catalog only: visitors browse and contact the company;
# there is no cart or checkout yet.
class Storefront < ApplicationRecord
  include Tenantable

  audited associated_with: :company

  # Labels that could collide with the platform's own hosts. Extend per deploy
  # with STOREFRONT_RESERVED_SUBDOMAINS (comma-separated) when the storefront
  # domain is shared with the app itself.
  RESERVED_SUBDOMAINS = %w[
    www app admin api mail smtp ftp static assets cdn staging dev test help support status blog docs
  ].freeze
  SUBDOMAIN_FORMAT = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/
  IMAGE_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_IMAGE_SIZE = 10.megabytes

  has_one_attached :logo do |attachable|
    attachable.variant :header, resize_to_limit: [320, 320], preprocessed: true
  end
  has_one_attached :banner do |attachable|
    attachable.variant :hero, resize_to_limit: [1600, 600], preprocessed: true
  end

  before_validation :normalize_subdomain

  validates :company_id, uniqueness: true
  validates :subdomain, format: { with: SUBDOMAIN_FORMAT }, allow_nil: true
  validates :subdomain, uniqueness: { case_sensitive: false }, allow_nil: true
  validate :subdomain_not_reserved
  validate :images_are_acceptable

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

  def contact_present?
    phone.present? || whatsapp_number.present? || email.present? || address.present?
  end

  private

  def normalize_subdomain
    self.subdomain = subdomain.to_s.strip.downcase.presence
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
