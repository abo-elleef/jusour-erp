# frozen_string_literal: true

class PurchaseOrder < ApplicationRecord
  include AASM

  belongs_to :supplier
  belongs_to :user
  has_many :purchase_order_items, dependent: :destroy

  accepts_nested_attributes_for :purchase_order_items, allow_destroy: true,
    reject_if: proc { |attrs| attrs["ingredient_id"].blank? }

  monetize :total_cents

  before_validation :assign_po_number, on: :create
  before_save :recalculate_total

  aasm column: :status do
    state :draft, initial: true
    state :sent
    state :partially_received
    state :received
    state :cancelled

    event :send_to_supplier do
      transitions from: :draft, to: :sent
      after { update_column(:ordered_on, Date.current) }
    end

    event :mark_partially_received do
      transitions from: :sent, to: :partially_received
    end

    event :mark_received do
      transitions from: %i[sent partially_received], to: :received
    end

    event :cancel do
      transitions from: %i[draft sent], to: :cancelled
    end
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[po_number status ordered_on supplier_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[supplier]
  end

  private

  def assign_po_number
    return if po_number.present?

    last = PurchaseOrder.where("po_number LIKE ?", "PO-%").order(:created_at).last
    num = last ? last.po_number.delete_prefix("PO-").to_i + 1 : 1
    self.po_number = format("PO-%04d", num)
  end

  def recalculate_total
    self.total_cents = purchase_order_items.sum { |i| (i.quantity_ordered.to_d * i.unit_price_cents).round }
  end
end
