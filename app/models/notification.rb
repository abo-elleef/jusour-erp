# frozen_string_literal: true

class Notification < ApplicationRecord
  include Tenantable

  self.inheritance_column = :_type_disabled

  belongs_to :recipient, polymorphic: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def message
    params["message"] || params[:message]
  end

  def ingredient
    id = params["ingredient_id"] || params[:ingredient_id]
    Ingredient.find_by(id: id) if id.present?
  end

  def unread?
    read_at.nil?
  end

  def mark_as_read!
    update!(read_at: Time.current)
  end
end
