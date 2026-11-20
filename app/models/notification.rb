# frozen_string_literal: true

class Notification < ApplicationRecord
  include Tenantable

  self.inheritance_column = :_type_disabled

  belongs_to :recipient, polymorphic: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # Live push to the recipient's open tabs. After commit, so a notification
  # created inside a transaction that rolls back never pops up.
  after_create_commit -> { push_live(popup: true) }
  after_update_commit -> { push_live(popup: false) }, if: :saved_change_to_read_at?

  # update_all (mark all read) skips callbacks; callers use this afterwards.
  def self.refresh_badge_for(user)
    Notifications::BroadcastJob.perform_later(user.id) if user.is_a?(User)
  end

  def message
    params["message"] || params[:message]
  end

  def ingredient
    id = params["ingredient_id"] || params[:ingredient_id]
    Ingredient.find_by(id: id) if id.present?
  end

  def customer_invoice
    id = params["customer_invoice_id"] || params[:customer_invoice_id]
    CustomerInvoice.find_by(id: id) if id.present?
  end

  def unread?
    read_at.nil?
  end

  def mark_as_read!
    update!(read_at: Time.current)
  end

  # Where "Open" on a popup goes: the record the notification is about, else
  # the notifications list.
  def target_path
    helpers = Rails.application.routes.url_helpers
    p = (params || {}).with_indifferent_access
    mp = (p[:message_params] || {}).with_indifferent_access
    if (id = p[:customer_invoice_id] || mp[:customer_invoice_id]).present?
      helpers.admin_sales_customer_invoice_path(id)
    elsif (id = p[:ticket_id] || mp[:ticket_id]).present?
      helpers.admin_sales_ticket_path(id)
    elsif (id = p[:lead_id] || mp[:lead_id]).present?
      helpers.admin_sales_lead_path(id)
    elsif (id = mp[:vendor_invoice_id]).present?
      helpers.admin_inventory_vendor_invoice_path(id)
    elsif (id = p[:ingredient_id] || mp[:ingredient_id]).present?
      helpers.admin_inventory_ingredient_path(id)
    else
      helpers.admin_notifications_path
    end
  end

  private

  def push_live(popup:)
    return unless recipient_type == "User"

    Notifications::BroadcastJob.perform_later(recipient_id, id, popup: popup)
  end
end
