# frozen_string_literal: true

# A logo printed at the top of customer receipts. Included by CompanySetting
# (the company-wide logo) and Location (a branch's own logo, which wins over
# the company's — see Printing::ReceiptLogo).
module HasReceiptLogo
  extend ActiveSupport::Concern

  # No SVG: ImageMagick would interpret it server-side, which is not worth the risk.
  RECEIPT_LOGO_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  RECEIPT_LOGO_MAX_SIZE = 5.megabytes

  included do
    has_one_attached :receipt_logo

    attr_reader :remove_receipt_logo

    validate :receipt_logo_is_acceptable
    after_save :purge_removed_receipt_logo
  end

  def remove_receipt_logo=(value)
    @remove_receipt_logo = ActiveModel::Type::Boolean.new.cast(value)
  end

  private

  def receipt_logo_is_acceptable
    return unless attachment_changes["receipt_logo"] && receipt_logo.attached?

    blob = receipt_logo.blob
    errors.add(:receipt_logo, :invalid_image_type) unless RECEIPT_LOGO_CONTENT_TYPES.include?(blob.content_type)
    errors.add(:receipt_logo, :image_too_large) if blob.byte_size > RECEIPT_LOGO_MAX_SIZE
  end

  # "Remove" only applies when no replacement was uploaded in the same save.
  def purge_removed_receipt_logo
    return unless remove_receipt_logo && receipt_logo.attached?
    return if attachment_changes["receipt_logo"]

    receipt_logo.purge_later
  end
end
