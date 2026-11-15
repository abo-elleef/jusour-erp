# frozen_string_literal: true

# A zone a branch delivers self-orders to, with its own delivery fee. The
# customer picks one at checkout; the fee in force then is copied onto the order,
# so editing or removing an area later never changes past orders.
class DeliveryArea < ApplicationRecord
  include Tenantable
  include MoneyInputs

  INDEX_SORTABLE_COLUMNS = %w[position name fee_cents active created_at].freeze
  INDEX_DEFAULT_SORT = "position"

  belongs_to :location

  # A blank fee field means "free delivery", not "no fee recorded": the column is
  # NOT NULL, and money_input turns a blank *_pounds into nil.
  before_validation { self.fee_cents ||= 0 }
  before_validation { self.position ||= 0 }

  validates :name, presence: true, uniqueness: { scope: :location_id, case_sensitive: false }
  validates :fee_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :position, numericality: { only_integer: true }
  validate :location_is_a_branch

  money_input :fee_cents

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  def display_name(locale = I18n.locale)
    locale.to_s == "ar" && name_ar.present? ? name_ar : name
  end

  private

  def location_is_a_branch
    return if location.nil? || location.branch?

    errors.add(:location, I18n.t("admin.delivery_areas.errors.must_be_branch"))
  end
end
