# frozen_string_literal: true

# Public storefront copy is kept in two columns: the plain one is the English
# version, the *_ar one the Arabic. Visitors get their language and fall back to
# the other one when it's blank, so a site filled in one language still reads.
module StorefrontLocalized
  extend ActiveSupport::Concern

  def localized(attribute, locale: I18n.locale)
    english = public_send(attribute).to_s
    arabic = public_send(:"#{attribute}_ar").to_s
    locale.to_s == "ar" ? arabic.presence || english : english.presence || arabic
  end
end
