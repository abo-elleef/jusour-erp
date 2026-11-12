# frozen_string_literal: true

module Printing
  module Escpos
    # The items table shared by kitchen, station and pick tickets: item name with its
    # quantity, then one detail line holding every modifier and the item's note.
    # The customer receipt uses the same detail line (TicketItemsTable.detail_lines).
    module TicketItemsTable
      MODIFIER_SEPARATOR = " • "
      NOTE_SEPARATOR     = " | "
      # Characters per detail line before wrapping; Arabic glyphs at the ticket size
      # are a little narrower than a text-mode column, minus the side padding.
      DETAIL_CHARS_RATIO = 0.95
      # Characters of an item name per line at the ticket's bold item size before it
      # wraps, as a share of the text-mode width: the name column is 65% of the paper
      # and the glyphs are larger (ArabicImageRenderer::BOLD_LABEL_PT). 42 columns
      # gives 29; a 30-character Arabic name is about the most that fits.
      ITEM_NAME_CHARS_RATIO = 0.7

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

        items.each do |item|
          # Name and quantity bold and large; a long name wraps, the quantity stays on
          # its first line.
          first, *rest = TicketItemsTable.wrap(item.display_name.to_s, item_name_chars)
          doc.row(first, item.quantity.to_s, padded: true, bold_value: true, bold_label: true, value_column: true)
          rest.each { |line| doc.row(line, "", padded: true, bold_label: true, value_column: true) }
          detail_lines(item).each { |line| doc.modifier_text(line, columns: 2, padded: true) }
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
