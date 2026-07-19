# frozen_string_literal: true

class Printer < ApplicationRecord
  include Tenantable

  PRINTER_TYPES = %w[receipt kitchen bar expo].freeze
  PRODUCTION_TYPES = %w[kitchen bar].freeze
  CONNECTION_TYPES = %w[network usb].freeze
  PAPER_WIDTHS = %w[58mm 80mm].freeze

  belongs_to :location
  has_many :print_logs, dependent: :nullify
  has_many :printer_menu_items, dependent: :destroy
  has_many :menu_items, through: :printer_menu_items

  validates :name, presence: true
  validates :printer_type, presence: true, inclusion: { in: PRINTER_TYPES }
  validates :connection_type, presence: true, inclusion: { in: CONNECTION_TYPES }
  validates :paper_width, inclusion: { in: PAPER_WIDTHS }
  validates :port, numericality: { only_integer: true, greater_than: 0, less_than: 65_536 }, allow_nil: true
  validates :host, presence: true, if: :network?
  validates :host, presence: true, if: :usb?,
            format: { with: /\A[A-Za-z0-9]+\z/, message: :usb_device_format },
            allow_blank: false
  validate :host_format, if: :network?

  scope :active, -> { where(active: true) }
  scope :defaults, -> { where(is_default: true) }
  scope :production_stations, -> { active.where(printer_type: PRODUCTION_TYPES) }
  scope :for_location, lambda { |location|
    if location.present?
      where(location_id: location.id)
    else
      none
    end
  }

  before_validation :normalize_host, :clear_default_if_inactive
  before_save :unset_other_defaults, if: -> { is_default? && active? }

  def network?
    connection_type == "network"
  end

  def usb?
    connection_type == "usb"
  end

  def connection_summary
    if network?
      [host, port].compact.join(":")
    else
      host.present? ? "USB — #{host}" : I18n.t("printers.connection_types.usb")
    end
  end

  def self.default_for(type, location:)
    return nil if location.blank?

    scope = active.for_location(location).where(printer_type: type)
    scope.where(is_default: true).first || scope.order(:created_at).first
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name printer_type connection_type station active is_default created_at location_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[menu_items location]
  end

  def production_station?
    PRODUCTION_TYPES.include?(printer_type)
  end

  private

  def normalize_host
    self.host = host.to_s.strip.upcase.presence if usb?
    self.host = host.to_s.strip.presence if network?
    self.port = nil if usb?
  end

  def clear_default_if_inactive
    self.is_default = false unless active?
  end

  def unset_other_defaults
    Printer.where(printer_type: printer_type, location_id: location_id, is_default: true)
           .where.not(id: id)
           .update_all(is_default: false)
  end

  def host_format
    return if host.blank?

    errors.add(:host, :invalid) unless host.match?(/\A[\w.\-]+\z/)
  end
end
