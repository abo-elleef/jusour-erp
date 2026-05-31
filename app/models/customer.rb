# frozen_string_literal: true

class Customer < ApplicationRecord
  has_many :orders, dependent: :nullify
  has_many :loyalty_transactions, dependent: :destroy
  has_many :addresses, class_name: "CustomerAddress", dependent: :destroy, inverse_of: :customer

  accepts_nested_attributes_for :addresses, allow_destroy: true,
    reject_if: proc { |attrs| attrs["address"].to_s.strip.blank? }

  validates :email, uniqueness: true, allow_blank: true
  validates :phone, uniqueness: true, allow_blank: true
  validates :phone_secondary, uniqueness: true, allow_blank: true
  validate :email_or_phone_present
  validate :phones_must_differ

  monetize :total_spent_cents, allow_nil: false

  def self.ransackable_attributes(_auth_object = nil)
    %w[name email phone phone_secondary loyalty_points total_spent_cents created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[addresses]
  end

  def display_name
    name.presence || phone.presence || phone_secondary.presence || email.presence || "Customer"
  end

  def default_address
    addresses.find_by(is_default: true) || addresses.ordered.first
  end

  def contact_phones
    [phone, phone_secondary].compact_blank
  end

  private

  def email_or_phone_present
    return if email.present? || phone.present?

    errors.add(:base, I18n.t("customers.errors.email_or_phone_required"))
  end

  def phones_must_differ
    return if phone.blank? || phone_secondary.blank?
    return unless phone == phone_secondary

    errors.add(:phone_secondary, I18n.t("customers.errors.phones_must_differ"))
  end
end
