# frozen_string_literal: true

vips_available = begin
  require "vips"
  Vips.get_suffixes
  true
rescue LoadError, StandardError
  false
end

Rails.application.config.active_storage.variant_processor = vips_available ? :vips : :mini_magick
