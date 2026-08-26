# frozen_string_literal: true

module Inventory
  class NotifyPriceChangeJob < ApplicationJob
    queue_as :default

    def perform(ingredient_id, supplier_id, old_cents, new_cents, invoice_id)
      ingredient = Ingredient.unscoped.find(ingredient_id)

      with_company(ingredient.company) do
        old_cents = old_cents.to_i
        new_cents = new_cents.to_i
        return if old_cents.zero?

        supplier = Supplier.find_by(id: supplier_id)
        invoice = VendorInvoice.find_by(id: invoice_id)

        percent = (((new_cents - old_cents).to_d / old_cents) * 100).round(1).to_f
        direction = new_cents >= old_cents ? "up" : "down"

        Inventory::NotifyService.deliver_to_managers(
          ingredient: ingredient,
          message_key: "price_change",
          message_params: {
            name: ingredient.name,
            supplier: supplier&.name,
            supplier_id: supplier&.id,
            old_price_cents: old_cents,
            new_price_cents: new_cents,
            percent: percent.abs,
            direction: direction,
            invoice_number: invoice&.invoice_number,
            vendor_invoice_id: invoice&.id
          }
        )
      end
    end
  end
end
