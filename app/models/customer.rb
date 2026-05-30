# frozen_string_literal: true

class Customer < ApplicationRecord
  has_many :orders, dependent: :nullify
  has_many :loyalty_transactions, dependent: :destroy

  validates :email, uniqueness: true, allow_blank: true
  validates :phone, uniqueness: true, allow_blank: true
  validate :email_or_phone_present

  def email_or_phone_present
    return if email.present? || phone.present?

    errors.add(:base, "Email or phone is required")
  end

  monetize :total_spent_cents, allow_nil: false

  def self.ransackable_attributes(_auth_object = nil)
    %w[name email phone loyalty_points total_spent_cents created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  def display_name
    name.presence || phone.presence || email.presence || "Customer"
  end
end
