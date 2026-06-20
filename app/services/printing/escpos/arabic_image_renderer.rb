# frozen_string_literal: true

require "open3"

module Printing
  module Escpos
    # Renders Arabic text (and logos) as ESC/POS raster image bytes.
    #
    # Thermal printers cannot shape Arabic letters internally — each character
    # prints as an isolated glyph. The only reliable fix is to render text as
    # a bitmap using the OS font stack (which handles Arabic joining and RTL),
    # then send the bitmap via the ESC/POS GS v 0 raster image command.
    module ArabicImageRenderer
      PAPER_PX_WIDTH = { 42 => 576, 32 => 384 }.freeze
      FONT_SIZE_PT   = 26

      CANDIDATE_FONTS = [
        # Bundled fallback — drop NotoNaskhArabic-Regular.ttf into vendor/fonts/
        Rails.root.join("vendor/fonts/NotoNaskhArabic-Regular.ttf").to_s,
        # Linux — apt-get install fonts-noto-core
        "/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf",
        "/usr/share/fonts/opentype/noto/NotoNaskhArabic-Regular.otf",
        "/usr/share/fonts/truetype/fonts-arabeyes/ae_AlArabiya.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
        # macOS
        "/System/Library/Fonts/Supplemental/Al Nile.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/GeezaPro.ttc"
      ].freeze

      module_function

      # Returns raw ESC/POS bytes for a single Arabic text line.
      # align: :left | :center | :right
      def render_line(text, doc_width: 42, align: :right)
        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        font     = arabic_font
        return nil unless font

        gravity = { left: "West", center: "Center", right: "East" }.fetch(align, "East")
        pbm     = render_pbm_single(text.to_s.strip, gravity, px_width, font)
        pbm ? pbm_to_escpos(pbm) : nil
      end

      # Returns raw ESC/POS bytes for a receipt row rendered as a single image:
      # Arabic label on the right, LTR value (price / qty) on the left.
      # This keeps both sides on the same baseline and gives a proper RTL layout.
      def render_row(arabic_label, ltr_value, doc_width: 42)
        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        font     = arabic_font
        return nil unless font

        pbm = render_pbm_multi(
          [
            { gravity: "West", offset: "+8+0", text: ltr_value.to_s },
            { gravity: "East", offset: "+8+0", text: arabic_label.to_s.strip }
          ],
          px_width, font
        )
        pbm ? pbm_to_escpos(pbm) : nil
      end

      # Returns raw ESC/POS bytes for a logo image.
      # source: file path or HTTP(S) URL to a PNG/JPEG/GIF image.
      def render_logo(source, doc_width: 42)
        return nil if source.blank?

        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        max_h    = (px_width / 2).to_s

        cmd = [
          im_command,
          source.to_s,
          "-resize", "#{px_width}x#{max_h}>",
          "-gravity", "Center",
          "-background", "white",
          "-extent", "#{px_width}x",
          "-type", "Bilevel",
          "pbm:-"
        ]

        stdout, _stderr, status = Open3.capture3(*cmd)
        stdout = stdout.b
        return nil unless status.success? && stdout.start_with?("P4".b)

        pbm_to_escpos(stdout)
      end

      # Returns the path to the first usable Arabic font, or nil.
      def arabic_font
        override = Printing::Config.arabic_font_path
        return override if override.present? && File.exist?(override)

        CANDIDATE_FONTS.find { |f| File.exist?(f) }
      end

      private

      # Auto-detect ImageMagick v7 (`magick`) vs v6 (`convert`).
      def im_command
        return @_im_command if defined?(@_im_command)

        @_im_command = system("which magick > /dev/null 2>&1") ? "magick" : "convert"
      end

      # Single text annotation.
      def render_pbm_single(text, gravity, px_width, font)
        cmd = [
          im_command,
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
        stdout = stdout.b
        status.success? && stdout.start_with?("P4".b) ? stdout : nil
      end

      # Multiple text annotations in one image (e.g. price left + Arabic label right).
      def render_pbm_multi(annotations, px_width, font)
        cmd = [
          im_command,
          "-size", "#{px_width}x#{FONT_SIZE_PT * 2}",
          "xc:white",
          "-font",      font,
          "-pointsize", FONT_SIZE_PT.to_s,
          "-fill",      "black"
        ]
        annotations.each do |ann|
          cmd += ["-gravity", ann[:gravity], "-annotate", ann.fetch(:offset, "+0+0"), ann[:text]]
        end
        cmd += ["-type", "Bilevel", "pbm:-"]

        stdout, _stderr, status = Open3.capture3(*cmd)
        stdout = stdout.b
        status.success? && stdout.start_with?("P4".b) ? stdout : nil
      end

      # Converts a binary PBM (P4) blob to ESC/POS GS v 0 raster bytes.
      def pbm_to_escpos(pbm)
        pbm = pbm.b
        nl  = "\n".b
        i1  = pbm.index(nl)
        i2  = pbm.index(nl, i1 + 1)
        w, h = pbm[i1 + 1, i2 - i1 - 1].split(" ".b).map(&:to_i)
        data    = pbm[i2 + 1, pbm.bytesize]
        w_bytes = (w / 8.0).ceil

        # ESC/POS GS v 0: \x1D v 0 m xL xH yL yH <data>
        escpos = +"\x1D\x76\x30\x00".b
        escpos << [w_bytes].pack("v")
        escpos << [h].pack("v")
        escpos << data[0, w_bytes * h]
        escpos
      end
    end
  end
end
