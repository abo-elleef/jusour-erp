# frozen_string_literal: true

if ENV["CLOUDINARY_URL"].present?
  Cloudinary.config_from_url(ENV["CLOUDINARY_URL"])
  Cloudinary.config.secure = true
end
