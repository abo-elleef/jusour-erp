# frozen_string_literal: true

# The branch's edit-orders and void-orders PINs, checked the same way wherever an
# order is reopened or voided (the register and the admin order page).
module BranchOrderPins
  extend ActiveSupport::Concern

  private

  # nil when the PIN is right and the order may be reopened; otherwise the reason.
  def unlock_error(location)
    return t("flash.pos.unlock.not_unlockable") unless @order.unlockable_for_edit?
    return t("flash.pos.unlock.pin_not_set") unless location&.edit_orders_pin_configured?
    return t("flash.pos.unlock.pin_locked") if location.edit_orders_pin_locked?
    return if location.verify_edit_orders_pin(params[:pin].to_s.strip)

    location.edit_orders_pin_locked? ? t("flash.pos.unlock.pin_locked") : t("flash.pos.unlock.wrong_pin")
  end

  # nil when the void-orders PIN is right; otherwise the reason it was refused.
  def void_pin_error(location)
    return t("flash.pos.void.pin_not_set") unless location&.void_orders_pin_configured?
    return t("flash.pos.unlock.pin_locked") if location.void_orders_pin_locked?
    return if location.verify_void_orders_pin(params[:pin].to_s.strip)

    location.void_orders_pin_locked? ? t("flash.pos.unlock.pin_locked") : t("flash.pos.unlock.wrong_pin")
  end

  def unlock!
    @order.update!(unlocked_for_edit_at: Time.current, unlocked_for_edit_by: current_user)
    AuditLogEntry.record!(action: "order.unlock_edit", record: @order, user: current_user)
  end
end
