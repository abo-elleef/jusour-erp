# frozen_string_literal: true

class PosController < ApplicationController
  include PosLocationScoped

  layout "pos"

  include FeatureGated

  before_action { require_feature!(:menu) }
  before_action :require_cashier!
  before_action :set_order, except: %i[new_order submit set_location set_workstation]
  before_action :ensure_order_persisted!, only: %i[update_fulfillment update_notes attach_customer apply_coupon manager_discount split merge]
  before_action :no_cache, only: :index

  def index
    authorize @order, :show?
    sync_order_location!
    @order.recalculate_totals! if @order.persisted?
    load_pos_menu
    @open_orders = Order.open_drafts.where(user: current_user).order(created_at: :desc).limit(10)
    @open_cash_session = current_user.open_cash_drawer_session
    @staff_users = User.active.order(:name)
  end

  def new_order
    authorize Order, :create?
    session.delete(:current_order_id)
    session.delete(:pending_order_params)
    redirect_to pos_path, status: :see_other
  end

  def apply_coupon
    authorize @order, :update?
    Discounts::ApplyDiscountService.call(order: @order, code: params[:code])
    redirect_to pos_path, notice: t("flash.pos.coupon_applied")
  rescue Discounts::ApplyDiscountService::InvalidDiscount => e
    redirect_to pos_path, alert: e.message
  end

  def manager_discount
    authorize @order, :update?
    pin = params[:pin].presence || ENV.fetch("MANAGER_PIN", "1234")
    manager = User.active.where(role: %w[owner manager]).find { |u| u.authenticate_pin(pin) }
    env_fallback = pin == ENV.fetch("MANAGER_PIN", "1234") && current_user.admin_access?
    unless manager || env_fallback
      return redirect_to pos_path, alert: t("flash.pos.invalid_manager_pin")
    end

    Discounts::ApplyDiscountService.call(
      order: @order,
      manager_override_cents: params[:amount_cents].to_i,
      description: "Manager Override"
    )
    redirect_to pos_path, notice: t("flash.pos.discount_applied")
  end

  def redeem_points
    authorize @order, :update?
    Loyalty::RedeemPointsService.call(order: @order)
    redirect_to pos_path, notice: t("flash.pos.points_redeemed")
  rescue Loyalty::RedeemPointsService::InsufficientPoints => e
    redirect_to pos_path, alert: e.message
  end

  def set_location
    location = @pos_locations.find { |loc| loc.id == params[:location_id] }
    unless location
      redirect_to pos_path, alert: t("flash.pos.invalid_location"), status: :see_other
      return
    end

    remember_pos_location!(location)
    session.delete(:pos_workstation_id)
    if (order = current_draft_order) && order.location_id != location.id
      session.delete(:current_order_id)
    end
    redirect_to pos_path, notice: t("flash.pos.location_changed", name: location.name), status: :see_other
  end

  def set_workstation
    workstation = @pos_workstations.find { |ws| ws.id == params[:workstation_id] }
    unless workstation
      redirect_to pos_path, alert: t("flash.pos.invalid_workstation"), status: :see_other
      return
    end

    remember_pos_workstation!(workstation)
    sync_draft_order_workstation!(workstation)
    redirect_to pos_path, notice: t("flash.pos.workstation_changed", name: workstation.name), status: :see_other
  end

  def submit
    order = current_draft_order
    return redirect_to pos_path, alert: t("flash.pos.no_active_order"), status: :see_other unless order

    authorize order, :submit?
    Orders::SubmitService.call(order)
    session.delete(:current_order_id)
    redirect_to pos_path, notice: t("flash.pos.sent_to_kitchen"), status: :see_other
  rescue Orders::SubmitService::InvalidFulfillment => e
    redirect_to pos_path, alert: e.message, status: :see_other
  end

  def update_notes
    authorize @order, :update?
    @order.update!(notes: params[:notes].to_s.strip.presence)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pos_path }
    end
  end

  def update_fulfillment
    authorize @order, :update?

    attrs = fulfillment_params.to_h
    # Never persist a delivery address without a customer
    attrs[:delivery_address] = nil if @order.customer.blank?

    if @order.update(attrs)
      # When switching to delivery with a customer who has a default address,
      # prefill the delivery address if not already set
      if @order.delivery? && @order.customer.present? && @order.delivery_address.blank?
        apply_customer_default_delivery_address!(@order.customer)
        @order.reload
      end
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to pos_path }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :update_fulfillment, status: :unprocessable_entity }
        format.html { redirect_to pos_path, alert: @order.errors.full_messages.to_sentence }
      end
    end
  end

  def attach_customer
    authorize @order, :update?

    if params[:clear].present?
      previous = @order.customer
      @order.update!(customer: nil, delivery_address: nil)
      drop_customer_standing_note!(previous)
      return respond_to_customer_attach
    end

    if params[:customer_id].present?
      customer = Customer.find(params[:customer_id])
      @order.update!(customer: customer)
      apply_customer_defaults!(customer)
      return respond_to_customer_attach
    end

    attrs = customer_params
    if customer_contact_blank?(attrs)
      return redirect_to pos_path, alert: t("flash.pos.customer_required")
    end

    customer = find_or_create_customer(attrs)
    if customer.persisted? && customer.errors.empty?
      @order.update!(customer: customer)
      apply_customer_defaults!(customer)
      respond_to_customer_attach
    else
      @customer_form_errors = customer.errors
      respond_to_customer_attach(status: :unprocessable_entity)
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to pos_path, alert: t("flash.pos.customer_not_found")
  end

  def split
    authorize @order, :split?
    new_order = Orders::CreateService.call(
      user: current_user,
      customer: @order.customer,
      location: @order.location,
      order_type: @order.order_type,
      table_number: @order.table_number,
      delivery_address: @order.delivery_address
    )
    item_ids = params[:order_item_ids] || []
    @order.order_items.where(id: item_ids).update_all(order_id: new_order.id)
    @order.recalculate_totals!
    new_order.recalculate_totals!
    session[:current_order_id] = new_order.id
    redirect_to pos_path, notice: t("flash.pos.order_split")
  end

  def merge
    authorize @order, :merge?
    other = Order.open_drafts.find(params[:other_order_id])
    other.order_items.update_all(order_id: @order.id)
    other.destroy
    @order.recalculate_totals!
    redirect_to pos_path, notice: t("flash.pos.orders_merged")
  end

  private

  def require_cashier!
    return if current_user&.can_access_pos?

    flash[:alert] = t("flash.pos_access")
    redirect_to root_path
  end

  def set_order
    @order = current_draft_order || build_pending_order!
    @order.recalculate_totals! if @order.persisted?
  end

  def current_draft_order
    return unless session[:current_order_id]

    Order.find_by(id: session[:current_order_id], status: "draft")
  end

  # Persists the pending order if it hasn't been saved yet (e.g. when the cashier
  # changes fulfillment type or attaches a customer before adding any items).
  def ensure_order_persisted!
    return if @order.persisted?

    pending = session.delete(:pending_order_params) || {}
    @order = Orders::CreateService.call(
      user:             current_user,
      location:         current_pos_location,
      order_type:       pending["order_type"].presence || "pickup",
      table_number:     pending["table_number"],
      delivery_address: pending["delivery_address"]
    )
    session[:current_order_id] = @order.id
  end

  # Returns an unsaved Order so nothing hits the DB until the first item is added.
  # Params are stored in the session and materialized by order_items_controller.
  def build_pending_order!
    session[:pending_order_params] = {
      "user_id"          => current_user.id,
      "location_id"      => current_pos_location&.id,
      "workstation_id"   => current_pos_workstation&.id,
      "order_type"       => "pickup",
      "status"           => "draft"
    }
    Order.new(
      user:             current_user,
      location:         current_pos_location,
      workstation:      current_pos_workstation,
      order_type:       "pickup",
      status:           "draft",
      subtotal_cents:   0,
      tax_cents:        0,
      discount_cents:   0,
      tip_cents:        0,
      total_cents:      0
    )
  end

  def sync_order_location!
    return if @pos_location.blank?
    return unless @order.persisted?

    attrs = {}
    attrs[:location] = @pos_location if @order.location_id != @pos_location.id
    if @pos_workstation.present? && @order.workstation_id != @pos_workstation.id
      attrs[:workstation] = @pos_workstation
    end
    @order.update!(attrs) if attrs.any?
  end

  def sync_draft_order_workstation!(workstation)
    order = current_draft_order
    return unless order&.persisted?

    order.update!(workstation: workstation)
  end

  def load_pos_menu
    menu = Menus::ForLocation.call(location: @pos_location)
    @categories = menu.categories
    @menu_items = menu.menu_items
    @combos = menu.combos
    @promos_by_item_id = menu.promos_by_item_id
  end

  def no_cache
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
    response.headers["Pragma"] = "no-cache"
  end

  def customer_params
    source = params[:customer].presence || params
    source.permit(
      :name, :email, :phone, :phone_secondary, :standing_note,
      addresses_attributes: %i[label address is_default]
    )
  end

  def find_or_create_customer(attrs)
    normalized = normalize_customer_attrs(attrs)
    phone = normalized[:phone]
    phone_secondary = normalized[:phone_secondary]
    email = normalized[:email]
    existing = find_customer_by_contact(phone: phone, phone_secondary: phone_secondary, email: email)
    return existing if existing

    Customer.create(normalized)
  end

  def normalize_customer_attrs(attrs)
    normalized = attrs.to_h.deep_symbolize_keys
    %i[name email phone phone_secondary].each do |key|
      next unless normalized.key?(key)

      normalized[key] = normalized[key].to_s.strip.presence
    end
    normalized
  end

  def customer_contact_blank?(attrs)
    attrs[:email].blank? && attrs[:phone].blank? && attrs[:phone_secondary].blank?
  end

  # Everything attaching a customer should carry onto the order.
  def apply_customer_defaults!(customer)
    apply_customer_default_delivery_address!(customer)
    apply_customer_standing_note!(customer)
  end

  # Seeds the order's note from the customer's standing one. Never overwrites: if
  # the cashier has already typed something, that is about this order and wins.
  def apply_customer_standing_note!(customer)
    return if customer.standing_note.blank?
    return if @order.notes.present?

    @order.update!(notes: customer.standing_note)
  end

  # Only removes the note if it is still verbatim that customer's. Once a cashier
  # has edited it, it is theirs and detaching the customer must not eat it.
  def drop_customer_standing_note!(previous_customer)
    return if previous_customer.blank?
    return if @order.notes.blank?
    return unless @order.notes == previous_customer.standing_note

    @order.update!(notes: nil)
  end

  def apply_customer_default_delivery_address!(customer)
    return unless @order.delivery?

    addr = customer.default_address
    return if addr.blank?

    @order.update!(delivery_address: addr.address) if @order.delivery_address.blank?
  end

  def find_customer_by_contact(phone:, phone_secondary:, email:)
    [phone, phone_secondary].compact_blank.each do |number|
      found = Customer.find_by(phone: number) || Customer.find_by(phone_secondary: number)
      return found if found
    end
    Customer.find_by(email: email) if email.present?
  end

  def respond_to_customer_attach(status: :ok)
    @order.recalculate_totals!
    respond_to do |format|
      format.turbo_stream { render :attach_customer, status: status }
      format.html { redirect_to pos_path }
    end
  end

  def fulfillment_params
    params.permit(:order_type, :table_number, :delivery_address)
  end
end
