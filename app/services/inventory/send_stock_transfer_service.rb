# frozen_string_literal: true

module Inventory
  class SendStockTransferService
    class InsufficientStockError < StandardError; end

    def initialize(transfer, user, line_quantities:)
      @transfer = transfer
      @user = user
      @line_quantities = line_quantities.transform_keys(&:to_s)
    end

    def call
      raise ActiveRecord::RecordInvalid, @transfer unless @transfer.requested?

      ActiveRecord::Base.transaction do
        @transfer.stock_transfer_lines.each do |line|
          qty = sent_quantity_for(line)
          validate_source_stock!(line, qty)
          line.update!(quantity_sent: qty)
        end

        @transfer.update!(
          status: "sent",
          sent_at: Time.current,
          sent_by: @user
        )
      end

      @transfer
    end

    private

    def sent_quantity_for(line)
      raw = @line_quantities[line.id.to_s]
      qty = raw.present? ? raw.to_d : line.quantity_requested.to_d
      raise ActiveRecord::RecordInvalid, line if qty.negative?

      qty
    end

    def validate_source_stock!(line, qty)
      return if qty.zero?

      available = line.available_at_source
      return if available >= qty

      line.errors.add(:quantity_sent, I18n.t("inventory.stock_transfers.errors.insufficient_stock",
        ingredient: line.ingredient.name, available: available, requested: qty))
      raise ActiveRecord::RecordInvalid, line
    end
  end
end
