# frozen_string_literal: true

class SupplierPriceHistory < ApplicationRecord
  belongs_to :supplier
  belongs_to :ingredient
  belongs_to :recorded_by_user, class_name: "User", optional: true
  # The invoice line this price came from. Nullable: rows recorded before the
  # link existed, and rows whose line was later deleted, keep NULL.
  belongs_to :vendor_invoice_line, optional: true

  # Newest first, with created_at breaking ties: two receipts can share an
  # effective_date (a morning and an evening delivery, or a backdated invoice
  # typed in later), and the price that stands is the one recorded last.
  scope :most_recent_first, -> { order(effective_date: :desc, created_at: :desc) }

  monetize :price_cents

  validates :effective_date, presence: true
end
