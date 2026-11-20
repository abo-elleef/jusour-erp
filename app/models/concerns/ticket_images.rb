# frozen_string_literal: true

# The image rules shared by a ticket and its comments: the same types and size
# limit as the waybill photo on a customer invoice, and at most MAX_COUNT.
module TicketImages
  CONTENT_TYPES = CustomerInvoice::WAYBILL_IMAGE_CONTENT_TYPES
  MAX_SIZE = CustomerInvoice::WAYBILL_IMAGE_MAX_SIZE
  MAX_COUNT = 10

  module_function

  def validate(record, images)
    return unless images.attached?

    blobs = images.map(&:blob)
    record.errors.add(:images, :too_many, count: MAX_COUNT) if blobs.size > MAX_COUNT
    record.errors.add(:images, :invalid_image_type) if blobs.any? { |b| CONTENT_TYPES.exclude?(b.content_type) }
    record.errors.add(:images, :image_too_large) if blobs.any? { |b| b.byte_size > MAX_SIZE }
  end
end
