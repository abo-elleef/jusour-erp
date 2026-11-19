# frozen_string_literal: true

module Admin
  module Sales
    class CreditNotesController < BaseController
      before_action :set_credit_note, only: %i[show confirm void]

      def index
        @pagy, @credit_notes = pagy(:offset, ownership.credit_notes(CreditNote.recent.includes(:customer)), limit: 50)
      end

      def new
        @credit_note = CreditNote.new(credit_note_date: Date.current, restock: true,
          location_id: Location.active.ordered.first&.id)
        @credit_note.credit_note_lines.build
        load_form_data
      end

      def create
        @credit_note = CreditNote.new(credit_note_params)
        @credit_note.user = current_user
        @credit_note.company ||= Current.company
        @credit_note.status = "draft"

        if documents_allowed?(@credit_note) && @credit_note.save
          if params[:commit_action] == "confirm"
            confirm_now(@credit_note)
          else
            redirect_to admin_sales_credit_note_path(@credit_note), notice: t("sales.credit_notes.flash.saved")
          end
        else
          load_form_data
          render :new, status: :unprocessable_entity
        end
      end

      def show; end

      def confirm
        confirm_now(@credit_note)
      end

      # A draft posts nothing yet, so voiding it is just marking it dead — never
      # a confirmed one, which already reduced the customer's balance.
      def void
        unless @credit_note.draft?
          return redirect_to admin_sales_credit_note_path(@credit_note),
            alert: t("sales.credit_notes.flash.cannot_void")
        end
        @credit_note.update!(status: "void")
        redirect_to admin_sales_credit_notes_path, notice: t("sales.credit_notes.flash.voided")
      end

      private

      def confirm_now(credit_note)
        ::Sales::ConfirmCreditNoteService.new(credit_note, current_user).call
        redirect_to admin_sales_credit_note_path(credit_note), notice: t("sales.credit_notes.flash.confirmed")
      rescue ::Sales::ConfirmCreditNoteService::Error => e
        redirect_to admin_sales_credit_note_path(credit_note), alert: e.message
      end

      # Someone else's credit note is a 404 for a rep (Sales::OwnershipScope).
      def set_credit_note
        @credit_note = ownership.credit_notes(CreditNote.all).find(params[:id])
      end

      def ownership
        @ownership ||= ::Sales::OwnershipScope.for(current_user)
      end

      # A rep can credit only their own customer, against an invoice they can see.
      def documents_allowed?(credit_note)
        if credit_note.customer_id.present? && !ownership.customers.exists?(id: credit_note.customer_id)
          credit_note.errors.add(:customer_id, t("sales.ownership.customer_not_yours"))
        end
        if credit_note.customer_invoice_id.present? && !ownership.invoices.exists?(id: credit_note.customer_invoice_id)
          credit_note.errors.add(:customer_invoice_id, t("sales.ownership.invoice_not_yours"))
        end
        credit_note.errors.empty?
      end

      def load_form_data
        @customers = ownership.customers.where(customer_type: "commercial").order(:name)
        @locations = Location.active.ordered
        @ingredients = Ingredient.active.order(:name)
        @invoices = ownership.invoices(CustomerInvoice.confirmed).recent.limit(200)
      end

      def credit_note_params
        params.require(:credit_note).permit(
          :customer_id, :location_id, :customer_invoice_id, :credit_note_date, :restock, :notes,
          credit_note_lines_attributes: %i[id ingredient_id quantity unit unit_price_pounds _destroy]
        )
      end
    end
  end
end
