# frozen_string_literal: true

class TreasuryTransfer < ApplicationRecord
  include Tenantable
  include MoneyInputs

  money_input :amount_cents

  belongs_to :from_treasury, class_name: "Treasury"
  belongs_to :to_treasury, class_name: "Treasury"
  belongs_to :user
  has_many :treasury_transactions, as: :source_record, dependent: :destroy

  monetize :amount_cents

  validates :description, :occurred_on, :amount_cents, presence: true
  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
  validate :from_and_to_must_differ
  validate :treasuries_must_be_active
  validate :from_treasury_has_sufficient_balance

  private

  def from_and_to_must_differ
    return if from_treasury_id.blank? || to_treasury_id.blank?
    return unless from_treasury_id == to_treasury_id

    errors.add(:to_treasury_id, :same_as_source)
  end

  def treasuries_must_be_active
    errors.add(:from_treasury_id, :inactive) if from_treasury && !from_treasury.active?
    errors.add(:to_treasury_id, :inactive) if to_treasury && !to_treasury.active?
  end

  def from_treasury_has_sufficient_balance
    return if from_treasury.blank? || amount_cents.blank?
    return if from_treasury.balance_cents >= amount_cents

    errors.add(:amount_cents, :insufficient_balance)
  end
end
