source "https://rubygems.org"

ruby "3.4.9"

gem "rails", "~> 7.1.5"
gem "sprockets-rails"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "jbuilder"
gem "redis"
gem "bootsnap", require: false
gem "image_processing", "~> 1.2"

# Auth & Authorization
gem "devise"
gem "pundit"

# Money & State
gem "money-rails"
gem "aasm"

# Payments
gem "stripe"

# Background Jobs
gem "sidekiq"

# File Upload
gem "cloudinary"
gem "google-cloud-storage", require: false

# Email & SMS
gem "sendgrid-ruby"
gem "twilio-ruby"

# Forms & UI
gem "simple_form"
gem "cocoon"

# i18n
gem "rails-i18n", "~> 7.0"

# Utilities
gem "pagy"
gem "ransack"
gem "chartkick"
gem "groupdate"
gem "csv"
gem "matrix"
gem "prawn"
gem "prawn-table"
gem "httparty"
gem "oauth2"
gem "dotenv-rails", groups: [:development, :test]

gem "tzinfo-data", platforms: %i[windows jruby]

group :development, :test do
  gem "debug", platforms: %i[mri windows]
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "shoulda-matchers"
end

group :development do
  gem "web-console"
end

gem "bidi", "~> 0.0.2"
