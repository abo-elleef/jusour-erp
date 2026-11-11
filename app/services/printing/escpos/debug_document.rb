# frozen_string_literal: true

module Printing
  module Escpos
    # Mirrors the Document public API but records every operation instead of
    # writing ESC/POS bytes. Used by PrintDebugController to render a browser
    # preview of what would be sent to the printer.
    #
    # Enable with: PRINT_DEBUG=true in your env.
    class DebugDocument
      ARABIC_PATTERN = /\p{Arabic}/

      attr_reader :entries, :config_summary

      def initialize(width: 42, charset: nil, compact: false)
        @width        = width
        @line_factor  = compact ? ArabicImageRenderer::COMPACT_LINE_FACTOR : ArabicImageRenderer::DEFAULT_LINE_FACTOR
        @charset_config = Charset.resolve(charset)
        @rtl          = @charset_config[:reshape]
        @use_images   = @rtl && ArabicImageRenderer.arabic_font.present?
        @current_align = :left
        @current_bold  = false
        @current_dh    = false
        @entries       = []

        @config_summary = {
          use_images: @use_images,
          rtl: @rtl,
          font_path: ArabicImageRenderer.arabic_font || "(none — TEXT mode will be used)",
          charset: @charset_config[:encoding].name,
          code_page: @charset_config[:code_page],
          paper_width_chars: @width
        }
      end

      # ── Public interface (same as Document) ──────────────────────────────

      def text(line = "")
        str = line.to_s
        if @use_images && str.match?(ARABIC_PATTERN)
          visual = Printing::Escpos::Bidi.visual_for_print(str, reshape: true)
          png = ArabicImageRenderer.render_png(visual, doc_width: @width, align: @current_align, font_scale: @current_dh ? 2 : 1,
                                               line_factor: @line_factor)
          push kind: :image, content: str, png_b64: png
        else
          push kind: :text, content: str
        end
      end

      def blank(lines = 1)
        lines.times { push kind: :blank, content: "" }
      end

      def row(left, right = "", padded: false, bold_value: false, value_column: false)
        if @use_images && (left.to_s.match?(ARABIC_PATTERN) || right.to_s.match?(ARABIC_PATTERN))
          visual_label = Printing::Escpos::Bidi.visual_for_print(left.to_s, reshape: true)
          visual_right = right.to_s.match?(ARABIC_PATTERN) ? Printing::Escpos::Bidi.visual_for_print(right.to_s, reshape: true) : right.to_s
          center_x = value_column ? Document.value_column_center(@width) : nil
          png = ArabicImageRenderer.render_row_png(visual_label, visual_right, doc_width: @width,
                                                   pad: padded ? Document::PAD_DOTS : 8, bold_value: bold_value,
                                                   line_factor: @line_factor, value_center_x: center_x)
          push kind: :image_row, left: left.to_s, right: right.to_s, png_b64: png
        else
          left_str  = left.to_s
          right_str = right.to_s
          left_str, right_str = right_str, left_str if @rtl
          push kind: :text_row, left: left_str, right: right_str
        end
      end

      def row3(label, center, value)
        if @use_images && (label.to_s.match?(ARABIC_PATTERN) || value.to_s.match?(ARABIC_PATTERN))
          visual_label  = Printing::Escpos::Bidi.visual_for_print(label.to_s,  reshape: true)
          visual_center = Printing::Escpos::Bidi.visual_for_print(center.to_s, reshape: true)
          v = value.to_s
          visual_value  = v.match?(/[a-zA-Z0-9]/) ? v : Printing::Escpos::Bidi.visual_for_print(v, reshape: true)
          png = ArabicImageRenderer.render_row3_png(visual_label, visual_center, visual_value, doc_width: @width)
          push kind: :image_row3, label: label.to_s, center: center.to_s, value: value.to_s, png_b64: png
        else
          left_str, right_str = @rtl ? [value.to_s, label.to_s] : [label.to_s, value.to_s]
          push kind: :text_row3, left: left_str, center: center.to_s, right: right_str
        end
      end

      def modifier_text(line = "", columns: 3, padded: false)
        str = line.to_s
        if @use_images
          visual = Printing::Escpos::Bidi.visual_for_print(str, reshape: true)
          png = ArabicImageRenderer.render_modifier_row_png(visual, doc_width: @width, columns: columns,
                                                            pad: padded ? Document::PAD_DOTS : 8,
                                                            line_factor: @line_factor)
          push kind: :image, content: str, png_b64: png
        else
          push kind: :text, content: @rtl ? str : "  #{str}"
        end
      end

      def separator
        png = ArabicImageRenderer.render_separator_png(doc_width: @width)
        push kind: :separator, png_b64: png
      end

      def rule(char = "-")
        push kind: :rule, content: char * @width
      end

      def bold(on = true)
        @current_bold = on
      end

      def align(mode)
        @current_align = mode
      end

      def double_height(on = true)
        @current_dh = on ? true : false
      end

      # The preview draws the logo as a PNG every time; only real printing is cached.
      def receipt_logo(location:, company:)
        Printing::ReceiptLogo.with_source(location: location, company: company) do |source|
          logo(source)
          source.present?
        end
      rescue StandardError => e
        Rails.logger.warn("[Printing] logo skipped in preview: #{e.class}: #{e.message}")
        false
      end

      def logo(source)
        return if source.blank?
        png = ArabicImageRenderer.render_logo_png(source, doc_width: @width)
        push kind: :logo, source: source, png_b64: png
      end

      def cut; end

      def to_bytes
        "".b
      end

      private

      def push(entry)
        @entries << entry.merge(align: @current_align, bold: @current_bold, double_height: @current_dh)
      end
    end
  end
end
