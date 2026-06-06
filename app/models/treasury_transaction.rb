# frozen_string_literal: true

class TreasuryTransaction < ApplicationRecord
  KINDS = %w[expense income drawer_open drawer_reconcile adjustment transfer].freeze

  belongs_to :treasury
  belongs_to :user
  belongs_to :source_record, polymorphic: true, optional: true

  monetize :amount_cents
  monetize :balance_after_cents

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :description, :occurred_on, :amount_cents, presence: true
  validates :amount_cents, numericality: { other_than: 0 }

  scope :recent, -> { order(occurred_on: :desc, created_at: :desc) }
  scope :on_date_range, ->(start_date, end_date) { where(occurred_on: start_date..end_date) }

  def inflow?
    amount_cents.positive?
  end

  def outflow?
    amount_cents.negative?
  end
end
