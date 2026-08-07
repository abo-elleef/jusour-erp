# frozen_string_literal: true

require "csv"

module Admin
  module Inventory
    class VendorInvoicesController < BaseController
      before_action :set_vendor_invoice, only: %i[show export edit update record_payment void attach_invoice_image]

      def index
        authorize_inventory_index!(VendorInvoice)
        @q = VendorInvoice.ransack(params[:q])
        @filtered = params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
        @vendor_invoices = @q.result.includes(:supplier, :user, :location).recent.limit(200)
        scope = VendorInvoice.all
        @total_count = scope.count
        @unpaid_count = scope.unpaid.count
        @partially_paid_count = scope.partially_paid.count
        @paid_count = scope.paid.count
        @outstanding_total_cents = scope.outstanding.sum(Arel.sql("total_cents - amount_paid_cents"))
        @suppliers = Supplier.active.order(:name)
        @locations = Location.active.ordered
      end

      def show
        authorize_inventory!(:show)
        prepare_show
      end

      # Export the invoice details + line items as a CSV that Excel opens
      # natively (UTF-8 BOM so Arabic ingredient names render correctly).
      def export
        authorize_inventory!(:show)
        lines = @vendor_invoice.vendor_invoice_lines.includes(:ingredient)

        csv = CSV.generate do |out|
          out << [t("inventory.vendor_invoices.invoice_number"), @vendor_invoice.invoice_number]
          out << [t("inventory.vendor_invoices.supplier"), @vendor_invoice.supplier.name]
          out << [t("inventory.vendor_invoices.invoice_date"), l(@vendor_invoice.invoice_date)]
          out << [t("inventory.vendor_invoices.received_on"), l(@vendor_invoice.received_on)]
          out << [t("inventory.vendor_invoices.received_at"), @vendor_invoice.location&.name]
          out << [t("inventory.vendor_invoices.subtotal"), money_amount(@vendor_invoice.subtotal_cents)]
          out << [t("inventory.vendor_invoices.total"), money_amount(@vendor_invoice.total_cents)]
          out << []
          out << [
            t("inventory.vendor_invoices.form.ingredient"),
            t("inventory.ingredients.index.table.code"),
            t("inventory.vendor_invoices.form.quantity"),
            t("inventory.vendor_invoices.form.unit"),
            t("inventory.vendor_invoices.form.unit_price"),
            t("inventory.vendor_invoices.total"),
            t("inventory.vendor_invoices.form.batch_reference")
          ]
          lines.each do |line|
            out << [
              line.ingredient.name,
              line.ingredient.code,
              line.quantity,
              line.unit.presence || line.ingredient.unit,
              money_amount(line.unit_price_cents),
              money_amount(line.line_total_cents),
              line.batch_reference
            ]
          end
        end

        send_data "﻿#{csv}",
          filename: "#{@vendor_invoice.invoice_number}.csv",
          type: "text/csv; charset=utf-8"
      end

      def new
        @vendor_invoice = VendorInvoice.new(
          user: current_user,
          invoice_date: Date.current,
          received_on: Date.current,
          invoice_number: VendorInvoice.next_invoice_number
        )
        authorize_inventory!(:create)
        prefill_supplier if params[:supplier_id].present?
        build_line_items
        load_form_data
        @vendor_invoice.location ||= default_receive_location
      end

      def create
        @vendor_invoice = VendorInvoice.new(vendor_invoice_params.merge(user: current_user))
        authorize_inventory!(:create)
        freight = extract_freight_options!

        if invoice_lines_present?
          ::Inventory::ReceiveVendorInvoiceService.new(
            @vendor_invoice,
            current_user,
            freight_amount_cents: freight[:amount_cents],
            freight_treasury: freight[:treasury]
          ).call
          redirect_to admin_inventory_vendor_invoice_path(@vendor_invoice),
            notice: t("flash.vendor_invoice.created")
        else
          @vendor_invoice.errors.add(:base, t("inventory.vendor_invoices.errors.lines_required"))
          build_line_items
          load_form_data
          render :new, status: :unprocessable_entity
        end
      rescue ::Accounting::SyncVendorInvoiceFreightService::Error => e
        @vendor_invoice.errors.add(:base, e.message)
        build_line_items
        load_form_data
        render :new, status: :unprocessable_entity
      rescue ActiveRecord::RecordInvalid
        build_line_items
        load_form_data
        render :new, status: :unprocessable_entity
      end

      def edit
        authorize_inventory!(:update)
        unless @vendor_invoice.fully_editable?
          redirect_to admin_inventory_vendor_invoice_path(@vendor_invoice),
            alert: edit_blocked_message
          return
        end
        build_line_items
        load_form_data
      end

      def update
        authorize_inventory!(:update)
        unless @vendor_invoice.fully_editable?
          redirect_to admin_inventory_vendor_invoice_path(@vendor_invoice),
            alert: edit_blocked_message
          return
        end

        if invoice_lines_present?(vendor_invoice_params)
          freight = extract_freight_options!
          ::Inventory::UpdateVendorInvoiceService.new(
            @vendor_invoice,
            current_user,
            vendor_invoice_params,
            freight_amount_cents: freight[:amount_cents],
            freight_treasury: freight[:treasury]
          ).call
          redirect_to admin_inventory_vendor_invoice_path(@vendor_invoice),
            notice: t("flash.vendor_invoice.updated")
        else
          @vendor_invoice.errors.add(:base, t("inventory.vendor_invoices.errors.lines_required"))
          build_line_items
          load_form_data
          render :edit, status: :unprocessable_entity
        end
      rescue Inventory::UpdateVendorInvoiceService::Error => e
        build_line_items
        load_form_data
        flash.now[:alert] = e.message
        render :edit, status: :unprocessable_entity
      rescue ::Accounting::SyncVendorInvoiceFreightService::Error => e
        build_line_items
        load_form_data
        flash.now[:alert] = e.message
        render :edit, status: :unprocessable_entity
      rescue ActiveRecord::RecordInvalid
        build_line_items
        load_form_data
        render :edit, status: :unprocessable_entity
      end

      def record_payment
        authorize_inventory!(:record_vendor_invoice_payment)
        treasury = Treasury.find(params[:treasury_id])
        payment_date = params[:payment_date].present? ? Date.parse(params[:payment_date]) : Date.current
        amount_cents = (BigDecimal(params[:payment_amount_dollars].to_s.presence || "0") * 100).round

        ::Accounting::RecordVendorInvoicePaymentService.new(
          vendor_invoice: @vendor_invoice,
          user: current_user,
          treasury: treasury,
          amount_cents: amount_cents,
          payment_date: payment_date
        ).call

        notice_key = @vendor_invoice.reload.paid? ? "flash.vendor_invoice.paid" : "flash.vendor_invoice.payment_recorded"
        redirect_to admin_inventory_vendor_invoice_path(@vendor_invoice), notice: t(notice_key)
      rescue ::Accounting::RecordVendorInvoicePaymentService::Error,
             ActiveRecord::RecordInvalid => e
        prepare_show
        flash.now[:alert] = e.message
        render :show, status: :unprocessable_entity
      end

      def void
        authorize_inventory!(:destroy)

        ::Accounting::UndoVendorInvoiceService.new(
          invoice: @vendor_invoice,
          user: current_user
        ).call

        redirect_to admin_inventory_vendor_invoices_path, notice: t("flash.vendor_invoice.voided")
      rescue ::Accounting::UndoVendorInvoiceService::Error => e
        redirect_to admin_inventory_vendor_invoice_path(@vendor_invoice), alert: e.message
      end

      def attach_invoice_image
        authorize_inventory!(:update)
        if @vendor_invoice.void?
          redirect_to admin_inventory_vendor_invoice_path(@vendor_invoice),
            alert: t("flash.vendor_invoice.cannot_attach_image")
          return
        end

        image = params.dig(:vendor_invoice, :invoice_image)
        if image.blank?
          redirect_to admin_inventory_vendor_invoice_path(@vendor_invoice),
            alert: t("flash.vendor_invoice.image_required")
          return
        end

        @vendor_invoice.invoice_image.attach(image)
        redirect_to admin_inventory_vendor_invoice_path(@vendor_invoice),
          notice: t("flash.vendor_invoice.image_attached")
      end

      private

      # Cents → plain decimal string (e.g. 34500 → "345.00") for spreadsheet cells.
      def money_amount(cents)
        format("%.2f", cents.to_d / 100)
      end

      def set_vendor_invoice
        @vendor_invoice = VendorInvoice.find(params[:id])
      end

      def prepare_show
        @lines = @vendor_invoice.vendor_invoice_lines.includes(:ingredient, :stock_batch)
        @payments = @vendor_invoice.vendor_invoice_payments.includes(:user, :treasury).order(payment_date: :desc, created_at: :desc)
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
        @freight_expense = @vendor_invoice.freight_expense
        @prev_invoice = @vendor_invoice.newer
        @next_invoice = @vendor_invoice.older

        @invoice_je = JournalEntry.for_source(@vendor_invoice).includes(:lines).first
        payment_jes = JournalEntry.includes(:lines).where(
          source_record_type: "VendorInvoicePayment",
          source_record_id: @payments.map(&:id)
        )
        @payment_jes = payment_jes.index_by(&:source_record_id)
        @freight_je = @freight_expense && JournalEntry.for_source(@freight_expense).includes(:lines).first
      end

      def prefill_supplier
        @vendor_invoice.supplier = Supplier.find_by(id: params[:supplier_id])
      end

      def build_line_items
        return if @vendor_invoice.vendor_invoice_lines.reject(&:marked_for_destruction?).any?

        @vendor_invoice.vendor_invoice_lines.build
      end

      def load_form_data
        @suppliers = Supplier.active.order(:name)
        @locations = Location.active.ordered
        @ingredients = Ingredient.active.includes(:ingredient_units).order(:name)
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
        @freight_expense = @vendor_invoice.freight_expense if @vendor_invoice.persisted?
        @ingredient_available_units = @ingredients.to_h do |i|
          [i.id, i.available_units.map { |u| [helpers.ingredient_unit_label(u), u] }]
        end
        @ingredient_shelf_life_days = @ingredients.each_with_object({}) do |ingredient, map|
          map[ingredient.id] = ingredient.shelf_life_days if ingredient.shelf_life_days.present?
        end
        @ingredient_unit_price_dollars = @ingredients.each_with_object({}) do |ingredient, map|
          cents = ingredient.cost_per_unit_cents.to_i
          next if cents.zero?

          map[ingredient.id] = (cents.to_d / 100).round(2)
        end
      end

      def default_receive_location
        Location.active.central_kitchens.ordered.first
      end

      # Freight is a linked Expense, not a VendorInvoice column. Strip virtual
      # fields before mass-assignment; sync runs after receive/update.
      def extract_freight_options!
        raw = params.fetch(:vendor_invoice, {})
        dollars = raw[:freight_amount_dollars]
        amount_cents = (BigDecimal(dollars.to_s.presence || "0") * 100).round
        treasury_id = raw[:freight_treasury_id].presence
        treasury = if treasury_id
                     Treasury.active.payable.visible_to(current_user).find_by(id: treasury_id)
                   end
        @freight_form_amount_cents = amount_cents
        @freight_form_treasury_id = treasury_id
        { amount_cents: amount_cents, treasury: treasury }
      end

      def vendor_invoice_params
        permitted = params.require(:vendor_invoice).permit(
          :supplier_id, :location_id, :invoice_number, :invoice_date, :received_on, :notes,
          :discount_type, :discount_value, :discount_amount_dollars, :discount_notes, :invoice_image,
          :adjustment_amount_dollars,
          :freight_amount_dollars, :freight_treasury_id,
          vendor_invoice_lines_attributes: %i[
            id ingredient_id quantity unit line_total_dollars expires_on batch_reference line_notes _destroy
          ]
        )
        permitted.delete(:freight_amount_dollars)
        permitted.delete(:freight_treasury_id)
        permitted[:vendor_invoice_lines_attributes]&.each_value do |attrs|
          dollars = attrs.delete(:line_total_dollars)
          attrs[:line_total_cents] = (BigDecimal(dollars.to_s.presence || "0") * 100).round
        end
        normalize_discount_params!(permitted)
        normalize_adjustment_params!(permitted)
        permitted
      end

      def normalize_adjustment_params!(permitted)
        dollars = permitted.delete(:adjustment_amount_dollars)
        permitted[:adjustment_cents] = (BigDecimal(dollars.to_s.presence || "0") * 100).round
      end

      def normalize_discount_params!(permitted)
        case permitted[:discount_type]
        when "fixed_amount"
          dollars = permitted.delete(:discount_amount_dollars)
          permitted[:discount_value] = (BigDecimal(dollars.to_s.presence || "0") * 100).round
        when "percentage"
          permitted.delete(:discount_amount_dollars)
        else
          permitted[:discount_type] = nil
          permitted[:discount_value] = nil
          permitted[:discount_notes] = nil
        end
      end

      def invoice_lines_present?(attrs = vendor_invoice_params)
        attrs[:vendor_invoice_lines_attributes]&.values&.any? do |line_attrs|
          line_attrs[:_destroy] != "1" && line_attrs[:ingredient_id].present?
        end
      end

      def edit_blocked_message
        if !@vendor_invoice.editable?
          t("inventory.vendor_invoices.errors.not_editable")
        else
          t("inventory.vendor_invoices.errors.stock_consumed_blocked")
        end
      end
    end
  end
end
