# frozen_string_literal: true

module Admin
  module Inventory
    class VendorCreditNotesController < BaseController
      before_action :set_vendor_credit_note, only: %i[show confirm void]

      def index
        authorize_inventory_index!(VendorCreditNote)
        @q = VendorCreditNote.ransack(params[:q])
        scope = @q.result.includes(:supplier, :user, :location, :vendor_invoice).recent
        @pagy, @vendor_credit_notes = pagy(:offset, scope, limit: 50)
        @suppliers = ::Supplier.active.order(:name)
      end

      def show
        authorize_inventory!(:show)
      end

      def new
        authorize_inventory!(:create)
        @vendor_credit_note = VendorCreditNote.new(
          credit_note_date: Date.current,
          kind: "goods_return",
          vendor_credit_note_lines: [VendorCreditNoteLine.new(position: 0)]
        )
        load_form_data
      end

      def create
        authorize_inventory!(:create)
        @vendor_credit_note = VendorCreditNote.new(vendor_credit_note_params)
        @vendor_credit_note.user = current_user

        if @vendor_credit_note.save
          redirect_to admin_inventory_vendor_credit_note_path(@vendor_credit_note),
            notice: t("inventory.vendor_credit_notes.created")
        else
          load_form_data
          render :new, status: :unprocessable_entity
        end
      end

      def confirm
        authorize_inventory!(:update)
        ::Inventory::ConfirmVendorCreditNoteService.call!(
          credit_note: @vendor_credit_note,
          user: current_user
        )
        redirect_to admin_inventory_vendor_credit_note_path(@vendor_credit_note),
          notice: t("inventory.vendor_credit_notes.confirmed")
      rescue ArgumentError => e
        redirect_to admin_inventory_vendor_credit_note_path(@vendor_credit_note),
          alert: e.message
      end

      # A draft posted nothing, so it just changes status. A confirmed note has
      # to unwind its invoice credit, AP balance, journal entry and stock, and is
      # owner-only.
      def void
        if @vendor_credit_note.confirmed?
          authorize_inventory!(:void_confirmed_vendor_credit_note)
          ::Inventory::VoidVendorCreditNoteService.call!(credit_note: @vendor_credit_note, user: current_user)
          return redirect_to admin_inventory_vendor_credit_note_path(@vendor_credit_note),
            notice: t("inventory.vendor_credit_notes.voided")
        end

        authorize_inventory!(:update)
        unless @vendor_credit_note.draft?
          return redirect_to admin_inventory_vendor_credit_note_path(@vendor_credit_note),
            alert: t("inventory.vendor_credit_notes.cannot_void")
        end
        @vendor_credit_note.update!(status: "void", voided_at: Time.current, voided_by: current_user)
        redirect_to admin_inventory_vendor_credit_notes_path,
          notice: t("inventory.vendor_credit_notes.voided")
      rescue ::Inventory::VoidVendorCreditNoteService::Error => e
        redirect_to admin_inventory_vendor_credit_note_path(@vendor_credit_note), alert: e.message
      end

      private

      def set_vendor_credit_note
        @vendor_credit_note = VendorCreditNote.find(params[:id])
      end

      def load_form_data
        @suppliers   = ::Supplier.active.order(:name)
        @locations   = ::Location.active.order(:name)
        @ingredients = ::Ingredient.active.includes(:ingredient_units).order(:name)
        @units       = ::Unit.ordered
        # Outstanding invoices per supplier, so the form can offer the invoice the
        # credit comes off and the JS can swap the list when the supplier changes.
        @supplier_open_invoices = ::VendorInvoice.posted.outstanding
          .order(invoice_date: :desc)
          .group_by(&:supplier_id)
          .transform_values do |invoices|
            invoices.map do |invoice|
              ["#{invoice.invoice_number} — #{helpers.format_amount(invoice.balance_due_cents)}", invoice.id]
            end
          end
        @ingredient_available_units = @ingredients.to_h do |i|
          [i.id, i.available_unit_records.map { |u| [helpers.ingredient_unit_label(u.name), u.id] }]
        end
      end

      def vendor_credit_note_params
        params.require(:vendor_credit_note).permit(
          :supplier_id, :credit_note_date, :notes, :kind, :location_id, :vendor_invoice_id,
          vendor_credit_note_lines_attributes: %i[
            id ingredient_id unit_id quantity line_total_pounds position line_notes _destroy
          ]
        )
      end
    end
  end
end
