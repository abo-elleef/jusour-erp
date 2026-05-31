# frozen_string_literal: true

class User < ApplicationRecord
  ROLES = %w[owner manager cashier kitchen].freeze

  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  validates :name, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }

  has_many :orders, dependent: :restrict_with_error
  has_many :stock_adjustments, dependent: :nullify
  has_many :purchase_orders, dependent: :nullify
  has_many :stock_takes, dependent: :nullify
  has_many :notifications, as: :recipient, dependent: :destroy
  has_many :processed_payments, class_name: "Payment", foreign_key: :processed_by_user_id, dependent: :nullify
  has_many :shift_logs, dependent: :nullify
  has_many :cash_drawer_sessions, dependent: :nullify
  has_many :expenses, dependent: :nullify

  monetize :hourly_rate_cents

  def clocked_in?
    shift_logs.active.exists?
  end

  def current_shift
    shift_logs.active.order(clocked_in_at: :desc).first
  end

  def owner?
    role == "owner"
  end

  def manager?
    role == "manager"
  end

  def cashier?
    role == "cashier"
  end

  def kitchen?
    role == "kitchen"
  end

  def admin_access?
    owner? || manager?
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name email role created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  def self.ransackable_scopes(_auth_object = nil)
    %w[name_or_email_cont]
  end

  scope :name_or_email_cont, lambda { |value|
    term = value.to_s.strip
    return all if term.blank?

    pattern = "%#{sanitize_sql_like(term)}%"
    where("users.name ILIKE :p OR users.email ILIKE :p", p: pattern)
  }

  def role_label
    role.humanize
  end
end
