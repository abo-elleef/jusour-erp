# frozen_string_literal: true

module MenuItemImageVariants
  extend ActiveSupport::Concern

  VARIANTS = {
    pos: 320,
    public_menu: 256
  }.freeze

  included do
    has_one_attached :image do |attachable|
      VARIANTS.each do |name, size|
        attachable.variant name, **transformations_for(size), preprocessed: true
      end
    end
  end

  class_methods do
    def transformations_for(size)
      base = { resize_to_fill: [size, size], format: :jpeg }

      if Rails.application.config.active_storage.variant_processor == :mini_magick
        base.merge(quality: 82)
      else
        base.merge(saver: { quality: 82 })
      end
    end
  end

  def image_for(variant)
    return unless image.attached?

    image.variant(variant)
  end
end
