# frozen_string_literal: true

module Printing
  module Escpos
    module Charset
      LATIN = {
        encoding: Encoding::Windows_1252,
        code_page: 16
      }.freeze

      ARABIC = {
        encoding: Encoding::Windows_1256,
        code_page: 47
      }.freeze

      module_function

      def arabic_locale?(locale = I18n.locale)
        locale.to_sym == :ar
      end

      def for_locale(locale = I18n.locale)
        arabic_locale?(locale) ? ARABIC : LATIN
      end

      def resolve(mode = nil)
        case (mode || Printing::Config.print_encoding).to_s
        when "windows-1256", "arabic" then ARABIC
        when "windows-1252", "latin" then LATIN
        else for_locale(I18n.locale)
        end
      end

      def code_page_for(config)
        override = Printing::Config.print_code_page
        return override if override.positive?

        config[:code_page]
      end
    end
  end
end
