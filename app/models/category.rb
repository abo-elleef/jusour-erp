# frozen_string_literal: true

class Category < ApplicationRecord
  include Tenantable

  has_many :menu_items, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :company_id }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }
end
