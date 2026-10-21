# frozen_string_literal: true

# One of the storefront's fixed info pages. There are exactly four slots and
# no way to add others: admins fill in and publish them, they don't build
# pages or menus. The body is Action Text, which Rails sanitizes on render —
# no scripts, styles or embeds reach the public site.
class StorefrontPage < ApplicationRecord
  include Tenantable
  include StorefrontLocalized

  audited associated_with: :company

  SLOTS = %w[about contact delivery_returns privacy].freeze

  belongs_to :storefront

  has_rich_text :body
  has_rich_text :body_ar

  validates :slot, inclusion: { in: SLOTS }, uniqueness: { scope: :storefront_id }

  before_validation { self.company_id ||= storefront&.company_id }

  scope :in_slot_order, -> { in_order_of(:slot, SLOTS) }

  # "delivery_returns" ⇄ /pages/delivery-returns
  def self.slot_from_param(param)
    slot = param.to_s.underscore
    slot if SLOTS.include?(slot)
  end

  def to_param_slot
    slot.dasherize
  end

  def display_title(locale: I18n.locale)
    localized(:title, locale: locale).presence || I18n.t("public.storefront.pages.#{slot}", locale: locale)
  end

  # The rich-text body for the visitor's language, or the other one when blank.
  def display_body(locale: I18n.locale)
    english = body if body.present? && body.to_plain_text.strip.present?
    arabic = body_ar if body_ar.present? && body_ar.to_plain_text.strip.present?
    locale.to_s == "ar" ? arabic || english : english || arabic
  end

  # Published and has something to show in some language.
  def live?
    enabled? && display_body.present?
  end
end
