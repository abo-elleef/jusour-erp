# frozen_string_literal: true

module Printing
  module Escpos
    module Charset
      LATIN = {
        encoding: Encoding::Windows_1252,
        code_page: 16,
        reshape: false
      }.freeze

      # Windows-1256 cannot encode Arabic Presentation Forms (U+FE70–U+FEFF),
      # so reshaping is disabled here. RTL reordering still applies.
      ARABIC = {
        encoding: Encoding::Windows_1256,
        code_page: 47,
        reshape: false
      }.freeze

      # UTF-8 mode: for printers that support UTF-8 natively (many modern Epson/Star).
      # Sends reshaped Arabic Presentation Form codepoints as UTF-8 — the printer
      # must have a Unicode Arabic font loaded. Code page 0 = printer default/UTF-8.
      ARABIC_UTF8 = {
        encoding: Encoding::UTF_8,
        code_page: 0,
        reshape: true
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
        when "utf-8", "arabic-utf8"   then ARABIC_UTF8
        when "windows-1252", "latin"  then LATIN
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
