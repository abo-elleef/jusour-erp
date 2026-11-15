# frozen_string_literal: true

module Printing
  module Escpos
    # The items table shared by kitchen, station and pick tickets: item name with its
    # quantity, then one detail line holding every modifier and the item's note.
    # The name is larger and heavier (ArabicImageRenderer::ITEM_NAME_PT); the detail
    # line is bold a step smaller (ITEM_DETAIL_PT), so the dish stands out first.
    # Lines print in OrderItem.in_menu_order, like the basket and the order pages.
    # The customer receipt uses the same detail line (TicketItemsTable.detail_lines).
    module TicketItemsTable
      MODIFIER_SEPARATOR = " • "
      NOTE_SEPARATOR     = " | "
      # Characters per detail line before wrapping, as a share of the text-mode width.
      # The line prints bold at ArabicImageRenderer::ITEM_DETAIL_PT across the full
      # paper: 0.95 fits at the regular 26pt, scaled by 26/28.
      DETAIL_CHARS_RATIO = 0.88
      # Characters of an item name per line at the ticket's bold item size before it
      # wraps, as a share of the text-mode width: the name column is 65% of the paper
      # and the glyphs are larger (ArabicImageRenderer::ITEM_NAME_PT). 0.7 fitted at
      # 32pt; scaled by 32/36 that is 0.62 — 26 characters on 80mm paper.
      ITEM_NAME_CHARS_RATIO = 0.62

      # "+ Double • Extra cheese | no sauce", wrapped at word boundaries to `limit`
      # characters so a long list never runs off the paper. [] for a plain item.
      def self.detail_lines(item, limit:)
        modifiers = item.order_item_modifiers.map(&:name).compact_blank
        parts = []
        parts << "+ #{modifiers.join(MODIFIER_SEPARATOR)}" if modifiers.any?
        parts << item.notes.to_s.squish if item.notes.present?
        return [] if parts.empty?

        wrap(parts.join(NOTE_SEPARATOR), limit)
      end

      SEPARATOR_TOKENS = ["+", MODIFIER_SEPARATOR.strip, NOTE_SEPARATOR.strip].freeze

      # A separator always travels with the word after it, so a wrapped line starts
      # with "| note" or "• modifier" and never ends on a dangling separator.
      def self.wrap(text, limit)
        words = text.split(" ").each_with_object([]) do |word, acc|
          if acc.any? && SEPARATOR_TOKENS.include?(acc.last)
            acc[-1] = "#{acc.last} #{word}"
          else
            acc << word
          end
        end
        words.each_with_object([+""]) do |word, lines|
          if lines.last.empty?
            lines.last << word
          elsif lines.last.length + 1 + word.length <= limit
            lines.last << " " << word
          else
            lines << word.dup
          end
        end
      end

      private

      def compose_items_table(doc, items)
        doc.align(:left)
        doc.separator
        doc.row(I18n.t("printing.receipt.item"), I18n.t("printing.receipt.qty"), padded: true, value_column: true)
        doc.separator

        name_style = { label_pt: ArabicImageRenderer::ITEM_NAME_PT, label_stroke: ArabicImageRenderer::ITEM_NAME_STROKE }
        OrderItem.in_menu_order(items).each do |item|
          # Name and quantity bold and large; a long name wraps, the quantity stays on
          # its first line. Modifiers and the note bold, a step smaller than the name.
          first, *rest = TicketItemsTable.wrap(item.display_name.to_s, item_name_chars)
          doc.row(first, item.quantity.to_s, padded: true, bold_value: true, bold_label: true, value_column: true,
                                              **name_style)
          rest.each { |line| doc.row(line, "", padded: true, bold_label: true, value_column: true, **name_style) }
          detail_lines(item).each do |line|
            doc.modifier_text(line, columns: 2, padded: true, bold: true, pt: ArabicImageRenderer::ITEM_DETAIL_PT)
          end
          doc.separator
        end
      end

      def item_name_chars
        (line_width * ITEM_NAME_CHARS_RATIO).floor
      end

      def detail_lines(item)
        TicketItemsTable.detail_lines(item, limit: (line_width * DETAIL_CHARS_RATIO).floor)
      end
    end
  end
end
