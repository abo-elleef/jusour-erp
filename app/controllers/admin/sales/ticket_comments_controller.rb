# frozen_string_literal: true

module Admin
  module Sales
    # A comment (with optional images) on a ticket's timeline. Same gates as
    # the ticket page: the ticket must be one this user can see.
    class TicketCommentsController < TicketsController
      skip_before_action :set_ticket, raise: false

      def create
        ticket = ownership.tickets(::Ticket.all).find(params[:ticket_id])
        ticket.add_comment!(by: current_user, body: params.dig(:ticket_comment, :body),
          images: params.dig(:ticket_comment, :images))
        redirect_to admin_sales_ticket_path(ticket, anchor: "ticket-timeline"), notice: t("tickets.flash.commented")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_sales_ticket_path(ticket), alert: e.record.errors.full_messages.to_sentence
      rescue ::Ticket::NotAllowed
        redirect_to admin_sales_ticket_path(ticket), alert: t("tickets.flash.not_allowed")
      end
    end
  end
end
