# frozen_string_literal: true

module Sales
  # Unlike Accounting::NotifyService/Inventory::NotifyService (which notify a
  # hardcoded role list — `User.where(role: %w[owner manager])`), this resolves
  # recipients by the actual permission grant. sales:confirm_payments is a
  # configurable permission (an owner can grant or revoke it per role), so a
  # hardcoded role list would silently drift from "whoever can actually
  # approve" the moment it's customized.
  class NotifyService
    def self.deliver_payment_pending(invoice)
      recipients_for("sales:confirm_payments").find_each do |user|
        Notification.create!(
          recipient: user, company: invoice.company, notification_type: "sales",
          # customer_invoice_id lives in both places on purpose: top-level is
          # what Notification#customer_invoice reads (mirrors #ingredient /
          # Inventory::NotifyService's ingredient_id), inside message_params is
          # what ApplicationHelper#notification_message reads to link the
          # invoice number inline in the message body.
          params: { message_key: "customer_invoice_payment_pending",
                    message_params: { invoice_number: invoice.invoice_number,
                                      customer_invoice_id: invoice.id }.deep_stringify_keys,
                    customer_invoice_id: invoice.id }
        )
      end
    end

    # Every active user in the current company whose role holds this
    # permission key. Relies on Current.company already being set (same
    # assumption the existing NotifyServices make) — Role/User are both
    # Tenantable, so this is already scoped to it.
    #
    # Resolves roles the way User#effective_role does: by the assigned role_id
    # first, and by the role string only for users with no role_id. Matching on
    # the string alone missed every user on a custom role, whose string is just
    # "custom".
    def self.recipients_for(permission_key)
      roles = Role.where("permissions @> ?", [permission_key].to_json)
      by_assigned = User.where(role_id: roles.select(:id))
      by_key      = User.where(role_id: nil, role: roles.select(:key))
      by_assigned.or(by_key).where(active: true)
    end
  end
end
