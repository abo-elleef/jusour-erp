# frozen_string_literal: true

module Printing
  module Escpos
    class Document
      ESC = "\x1B"
      GS  = "\x1D"

      ARABIC_PATTERN = /\p{Arabic}/
      # Side margin for padded rows: in dots for image rows (~4 mm at 203 dpi) and in
      # characters for plain-text rows.
      PAD_DOTS  = 32
      PAD_CHARS = 2

      def initialize(width: 42, charset: nil)
        @width = width
        # Binary from the start: raster image bytes and Windows-1256/UTF-8 text are
        # appended to the same buffer, and a UTF-8 buffer that picks up high bytes
        # turns BINARY and then rejects the next non-ASCII text line.
        @buffer = String.new(encoding: Encoding::BINARY)
        @charset_config = Charset.resolve(charset)
        @rtl = @charset_config[:rtl]
        # Image rendering is used when Arabic font is available (always preferred
        # for Arabic because ESC/POS printers can't shape Arabic glyphs themselves).
        @use_images = @rtl && ArabicImageRenderer.arabic_font.present?
        @current_align = :left
        @double_height = false
        init
      end

      def text(line = "")
        str = line.to_s
        if @use_images && str.match?(ARABIC_PATTERN)
          write_arabic_image(str, align: @current_align)
        else
          write_line(prepare_text(str))
        end
      end

      def blank(lines = 1)
        lines.times { write_line("") }
      end

      # padded: keep the row away from the paper edges (kitchen/station tickets).
      # bold_value: print the value (right-hand argument, e.g. a quantity) bold.
      def row(left, right = "", padded: false, bold_value: false)
        if @use_images && (left.to_s.match?(ARABIC_PATTERN) || right.to_s.match?(ARABIC_PATTERN))
          # Single image: Arabic label on right, LTR value (price) on left.
          write_arabic_row_image(left.to_s, right.to_s, padded: padded, bold_value: bold_value)
        else
          write_text_row(left, right, padded: padded, bold_value: bold_value)
        end
      end

      # Three-column receipt row: label (item name) | center (qty) | value (price).
      # In RTL image mode: label on right, qty in centre-left zone, value on left.
      def row3(label, center, value)
        if @use_images && (label.to_s.match?(ARABIC_PATTERN) || value.to_s.match?(ARABIC_PATTERN))
          write_arabic_row3_image(label.to_s, center.to_s, value.to_s)
        else
          label_str  = prepare_text(label)
          center_str = center.to_s
          value_str  = prepare_text(value)
          # RTL: value | center | label;  LTR: label | center | value
          left_str, right_str = @rtl ? [value_str, label_str] : [label_str, value_str]
          total = display_width(left_str) + display_width(center_str) + display_width(right_str)
          gap   = [(@width - total) / 2, 1].max
          write_line("#{left_str}#{' ' * gap}#{center_str}#{' ' * gap}#{right_str}")
        end
      end

      # Render a modifier/add-on line inside the item-name column with column borders.
      def modifier_text(line = "", columns: 3, padded: false)
        str = line.to_s
        if @use_images
          visual = Bidi.visual_for_print(str, reshape: true)
          bytes  = ArabicImageRenderer.render_modifier_row(visual, doc_width: @width, columns: columns,
                                                                   pad: padded ? PAD_DOTS : 8)
          return @buffer << bytes.b if bytes
        end
        # Text fallback
        margin = padded ? " " * PAD_CHARS : ""
        @rtl ? (align(:right); text("#{str}#{margin}"); align(:left)) : text("#{margin}  #{str}")
      end

      # Full-width horizontal line rendered as an image (used between table rows).
      def separator
        bytes = ArabicImageRenderer.render_separator(doc_width: @width)
        bytes ? @buffer << bytes.b : rule
      end

      def rule(char = "-")
        write_line(char * @width)
      end

      def bold(on = true)
        @buffer << ESC << "E" << (on ? "\x01" : "\x00")
      end

      def align(mode)
        @current_align = mode
        mode = rtl_align_mode(mode)
        code = { left: 0, center: 1, right: 2 }.fetch(mode)
        @buffer << ESC << "a" << code.chr
      end

      def double_height(on = true)
        @double_height = on ? true : false
        @buffer << GS << "!" << (on ? "\x11" : "\x00")
      end

      # Print the receipt logo for this branch (see ReceiptLogo.escpos). Returns
      # whether a logo was printed.
      # A logo problem (storage unreachable, ImageMagick error) never stops the print:
      # kitchen and station tickets carry the logo too, and a ticket without it is
      # far better than no ticket.
      def receipt_logo(location:, company:)
        bytes = Printing::ReceiptLogo.escpos(location: location, company: company, doc_width: @width)
        @buffer << bytes.b if bytes
        bytes.present?
      rescue StandardError => e
        Rails.logger.warn("[Printing] logo skipped: #{e.class}: #{e.message}")
        false
      end

      # Print a logo image from a file path or URL.
      # Falls back silently if ImageMagick or the source is unavailable.
      def logo(source)
        return if source.blank?

        bytes = ArabicImageRenderer.render_logo(source, doc_width: @width)
        @buffer << bytes.b if bytes
      end

      # Feed enough paper to clear the print head → cutter gap (~20 mm),
      # then perform a full cut. GS V 66 n feeds n × (paper motion unit) dots
      # before cutting; 150 dots ≈ 19 mm at 203 dpi (8 dots/mm).
      def cut
        @buffer << GS << "V" << "\x42" << 150.chr
      end

      def to_bytes
        @buffer.force_encoding(Encoding::BINARY)
      end

      private

      def init
        @buffer << ESC << "@"
        select_code_page
      end

      def select_code_page
        code_page = Charset.code_page_for(@charset_config)
        return if code_page.zero?

        @buffer << ESC << "t" << code_page.chr
      end

      def rtl_align_mode(mode)
        return mode unless @rtl

        case mode
        when :left  then :right
        when :right then :left
        else mode
        end
      end

      def prepare_text(value)
        return value.to_s unless @rtl

        Bidi.visual_for_print(value, reshape: @charset_config[:reshape])
      end

      def write_line(line)
        @buffer << encode_text(line).b << "\n"
      end

      def encode_text(value)
        str = value.to_s
        if @charset_config[:encoding] == Encoding::UTF_8
          str.encode(Encoding::UTF_8)
        else
          str.encode(
            @charset_config[:encoding],
            invalid: :replace,
            undef: :replace,
            replace: "?"
          )
        end
      end

      # Write Arabic text as a raster image line.
      # Pre-processes with reshape + bidi so ImageMagick (LTR renderer) displays
      # correctly: reshape assigns correct glyph forms, bidi reorders to visual order.
      def write_arabic_image(text, align: :right)
        visual = Bidi.visual_for_print(text, reshape: true)
        bytes  = ArabicImageRenderer.render_line(visual, doc_width: @width, align: align,
                                                         font_scale: @double_height ? 2 : 1)
        if bytes
          @buffer << bytes.b
        else
          write_line(prepare_text(text))
        end
      end

      # Render a receipt row as a single image: Arabic label on the right,
      # LTR value (price) on the left — both on the same baseline.
      # Only the Arabic label is reshaped/reordered; the price is passed as-is.
      def write_arabic_row_image(arabic_label, ltr_value, padded: false, bold_value: false)
        visual_label = Bidi.visual_for_print(arabic_label, reshape: true)
        visual_value = ltr_value.to_s.match?(ARABIC_PATTERN) ? Bidi.visual_for_print(ltr_value.to_s, reshape: true) : ltr_value.to_s
        bytes = ArabicImageRenderer.render_row(visual_label, visual_value, doc_width: @width,
                                                                          pad: padded ? PAD_DOTS : 8,
                                                                          bold_value: bold_value)
        if bytes
          @buffer << bytes.b
        else
          write_text_row(arabic_label, ltr_value, padded: padded, bold_value: bold_value)
        end
      end

      # Label on the reading side, value on the other; in RTL the value sits on the left.
      def write_text_row(label, value, padded: false, bold_value: false)
        margin    = padded ? " " * PAD_CHARS : ""
        label_str = prepare_text(label)
        value_str = prepare_text(value)
        space     = [@width - (2 * margin.length) - display_width(label_str) - display_width(value_str), 1].max
        value_out = bold_value ? "#{ESC}E\x01#{value_str}#{ESC}E\x00" : value_str
        left_out, right_out = @rtl ? [value_out, label_str] : [label_str, value_out]
        write_line("#{margin}#{left_out}#{' ' * space}#{right_out}#{margin}")
      end

      def display_width(value)
        value.to_s.length
      end

      def write_arabic_row3_image(label, center, value)
        visual_label  = Bidi.visual_for_print(label,  reshape: true)
        visual_center = Bidi.visual_for_print(center, reshape: true)
        # Price column is always LTR (Latin digits). Only apply bidi when the
        # value is pure Arabic text (e.g. the "السعر" column header).
        visual_value  = value.match?(/[a-zA-Z0-9]/) ? value : Bidi.visual_for_print(value, reshape: true)
        bytes = ArabicImageRenderer.render_row3(visual_label, visual_center, visual_value, doc_width: @width)
        if bytes
          @buffer << bytes.b
        else
          write_arabic_row_image("#{label} (#{center})", value)
        end
      end
    end
  end
end
