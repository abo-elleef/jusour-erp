# frozen_string_literal: true

require "open3"

module Printing
  module Escpos
    # Renders Arabic text as ESC/POS raster image bytes.
    #
    # Thermal printers (including SPRT) cannot shape Arabic letters internally —
    # they print each character as an isolated glyph. The only reliable fix is to
    # render the text as a bitmap using the OS font stack (which DOES handle Arabic
    # joining and RTL), then send the bitmap as a raster image command.
    #
    # ESC/POS raster command used: GS v 0 (standard across all ESC/POS printers).
    module ArabicImageRenderer
      # Pixel width keyed by document character width (42-char = 80mm, 32-char = 58mm)
      PAPER_PX_WIDTH = { 42 => 576, 32 => 384 }.freeze
      FONT_SIZE_PT   = 26

      # Ordered list of Arabic-capable fonts to try, most preferable first.
      # Add Linux/production paths here alongside macOS paths.
      CANDIDATE_FONTS = [
        # Linux — install with: apt-get install fonts-noto-core  OR  fonts-arabeyes
        "/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf",
        "/usr/share/fonts/truetype/fonts-arabeyes/ae_AlArabiya.ttf",
        "/usr/share/fonts/opentype/noto/NotoNaskhArabic-Regular.otf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
        # macOS
        "/System/Library/Fonts/Supplemental/Al Nile.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/GeezaPro.ttc"
      ].freeze

      module_function

      # Returns raw ESC/POS bytes (String, BINARY encoding) for one rendered line.
      # align: :left | :center | :right
      def render_line(text, doc_width: 42, align: :right)
        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        font     = arabic_font
        return nil unless font

        pbm = render_pbm(text.to_s.strip, px_width, font, align)
        return nil unless pbm

        pbm_to_escpos(pbm)
      end

      # Returns the path to the first usable Arabic font, or nil.
      def arabic_font
        override = Printing::Config.arabic_font_path
        return override if override.present? && File.exist?(override)

        CANDIDATE_FONTS.find { |f| File.exist?(f) }
      end

      private

      # Renders text to binary PBM (P4) via ImageMagick.
      def render_pbm(text, px_width, font, align)
        gravity = { left: "West", center: "Center", right: "East" }.fetch(align, "East")

        cmd = [
          "magick",
          "-size", "#{px_width}x#{FONT_SIZE_PT * 2}",
          "xc:white",
          "-font",      font,
          "-pointsize", FONT_SIZE_PT.to_s,
          "-fill",      "black",
          "-gravity",   gravity,
          "-annotate",  "+0+0", text,
          "-type",      "Bilevel",
          "pbm:-"
        ]

        stdout, _stderr, status = Open3.capture3(*cmd)
        stdout = stdout.b  # treat as raw binary
        status.success? && stdout.start_with?("P4".b) ? stdout : nil
      end

      # Converts a binary PBM (P4) blob to ESC/POS GS v 0 raster bytes.
      def pbm_to_escpos(pbm)
        pbm = pbm.b
        nl  = "\n".b
        i1  = pbm.index(nl)             # end of "P4" line
        i2  = pbm.index(nl, i1 + 1)    # end of "W H" line
        w, h = pbm[i1 + 1, i2 - i1 - 1].split(" ".b).map(&:to_i)
        data    = pbm[i2 + 1, pbm.bytesize]
        w_bytes = (w / 8.0).ceil

        # ESC/POS GS v 0 — raster bit image
        # \x1D v 0 m xL xH yL yH <data>
        escpos = +"\x1D\x76\x30\x00".b
        escpos << [w_bytes].pack("v")   # width in bytes, little-endian
        escpos << [h].pack("v")         # height in pixels, little-endian
        escpos << data[0, w_bytes * h]
        escpos
      end
    end
  end
end
