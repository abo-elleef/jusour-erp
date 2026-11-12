# frozen_string_literal: true

module Orders
  # Turns an order that was rung up in the browser while the internet was down into
  # a real, paid order.
  #
  # The customer already has their receipt and the kitchen already has its tickets,
  # so none of that is repeated here: the order is built directly and submitted
  # without going through SubmitService, which would print everything a second time.
  #
  # Safe to call again with the same payload. `client_uuid` is unique per company,
  # so a retry after a dropped response returns the order that was already made.
  class SyncOfflineOrderService
    Result = Struct.new(:success?, :order, :duplicate, :errors, keyword_init: true) do
      alias_method :duplicate?, :duplicate
    end

    # A device clock can be wrong. Believe it only within a window that is plausible
    # for an outage; anything outside it is stamped with the time it arrived.
    MAX_AGE = 3.days

    def self.call(user:, payload:)
      new(user: user, payload: payload).call
    end

    def initialize(user:, payload:)
      @syncing_user = user
      @payload = payload.with_indifferent_access
    end

    def call
      uuid = @payload[:client_uuid].to_s.strip
      return failure("client_uuid is required") if uuid.blank?

      existing = Order.find_by(client_uuid: uuid)
      return Result.new(success?: true, order: existing, duplicate: true, errors: []) if existing

      order = build_order(uuid)
      Result.new(success?: true, order: order, duplicate: false, errors: [])
    rescue ActiveRecord::RecordNotUnique
      Result.new(success?: true, order: Order.find_by(client_uuid: uuid), duplicate: true, errors: [])
    rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid, ArgumentError, AASM::InvalidTransition => e
      failure(e.message)
    end

    private

    def build_order(uuid)
      lines = Array(@payload[:items])
      raise ArgumentError, "Order has no items" if lines.empty?
      raise ArgumentError, I18n.t("order.submit.errors.table_number_required") if order_type == "table" && @payload[:table_number].blank?
      validate_delivery! if order_type == "delivery"

      Order.transaction do
        customer = delivery_customer if order_type == "delivery"
        order = Order.create!(
          user: cashier,
          customer: customer,
          delivery_address: (@payload[:delivery_address].to_s.strip if order_type == "delivery"),
          location: location,
          workstation: workstation,
          order_type: order_type,
          table_number: @payload[:table_number].presence,
          notes: @payload[:notes].presence,
          client_uuid: uuid,
          offline_number: @payload[:offline_number].presence,
          created_at: created_at,
          allow_table_clash: true
        )

        @price_differences = []
        lines.each { |line| add_line(order, line.with_indifferent_access) }
        order.recalculate_totals!
        record_payment(order)
        flag_price_differences(order)

        # `submit!` rather than SubmitService: same state change, no print job.
        order.submit!
        discard_replaced_draft(order)
        flag_table_clash(order)
        order.reload
      end
    end

    def add_line(order, line)
      quantity = [line[:quantity].to_i, 1].max
      menu_item = menu_item_for(line)
      combo = combo_for(line)
      item = order.order_items.create!(
        menu_item: menu_item,
        combo: combo,
        quantity: quantity,
        unit_price_cents: line[:unit_price_cents].to_i,
        notes: line_notes(line)
      )
      note_price_difference(item, menu_item, combo)

      Array(line[:modifiers]).each do |raw|
        modifier_row = raw.with_indifferent_access
        modifier = Modifier.find_by(id: modifier_row[:id])
        next unless modifier

        item.order_item_modifiers.create!(
          modifier: modifier,
          name: modifier_row[:name].presence || modifier.name,
          price_adjustment_cents: modifier_row[:price_adjustment_cents].to_i
        )
      end

      record_promo(order, item, line, quantity)
    end

    # The sale already happened at the price on the customer's receipt, so a price
    # that no longer matches the menu is recorded, not refused — menus do change
    # between the last snapshot and the moment the line drops. But the browser is
    # the one naming the price here, so anything that differs is left in the audit
    # trail for a manager to see.
    def note_price_difference(item, menu_item, combo)
      current = combo ? combo.price_cents : menu_item.price_cents_at(location)
      return if item.unit_price_cents == current

      @price_differences << { name: item.display_name, charged_cents: item.unit_price_cents, menu_cents: current }
    end

    def flag_price_differences(order)
      return if @price_differences.empty?

      AuditLogEntry.record!(
        action: "order.offline_price_differs",
        record: order,
        user: cashier,
        changes_snapshot: { lines: @price_differences, offline_number: order.offline_number }
      )
    end

    # Registers cannot see each other with the internet down, so two of them can
    # seat different customers at the same table, or one can seat a table that the
    # online register filled after the snapshot. Both orders are real and paid; the
    # table now holds two, the floor plan shows both, and this entry tells a
    # manager why.
    def flag_table_clash(order)
      other = order.table_conflict
      return unless other

      AuditLogEntry.record!(
        action: "order.offline_table_clash",
        record: order,
        user: cashier,
        changes_snapshot: {
          table_number: order.table_number,
          offline_number: order.offline_number,
          other_order_id: other.id,
          other_order_number: other.order_number
        }
      )
    end

    def record_promo(order, item, line, quantity)
      per_unit = line[:promo_discount_cents].to_i
      return unless per_unit.positive?

      promo = MenuPromo.find_by(id: line[:promo_id])
      order.order_discounts.create!(
        order_item_id: item.id,
        menu_promo_id: promo&.id,
        description: I18n.t("promos.order_discount_description", name: line[:promo_label].presence || promo&.name),
        amount_cents: per_unit * quantity
      )
    end

    # A modifier deleted since the snapshot was taken can no longer be attached, but
    # the kitchen was told about it. Keep it on the line as text rather than lose it.
    def line_notes(line)
      missing = Array(line[:modifiers]).map(&:with_indifferent_access).reject { |m| Modifier.exists?(id: m[:id]) }
      extra = missing.map { |m| "+ #{m[:name]}" }
      [line[:notes].presence, *extra].compact.join(" · ").presence
    end

    # The order was started on the online register and carried over when the
    # internet dropped, so the draft it started as is still on the server. This
    # order is that sale, now paid, so the draft goes — the same discard a cashier
    # does by hand, with the same audit entry. Only a draft nobody has paid for or
    # sent to the kitchen in the meantime: anything else is real work, and a
    # duplicate a person sorts out beats an order silently lost.
    def discard_replaced_draft(order)
      id = @payload[:replaces_order_id].presence
      return unless id

      draft = Order.lock.find_by(id: id, status: "draft", kitchen_sent_at: nil)
      return if draft.nil? || draft.payments.exists?

      AuditLogEntry.record!(
        action: "order.discard",
        record: draft,
        user: cashier,
        changes_snapshot: { replaced_by_order_id: order.id, offline_number: order.offline_number }
      )
      draft.destroy!
    end

    def record_payment(order)
      tendered = @payload[:tendered_cents].to_i
      amount = tendered.positive? ? tendered : order.total_cents.to_i

      order.payments.create!(
        payment_method: "cash",
        amount_cents: amount,
        tip_cents: 0,
        status: "completed",
        processed_by_user: cashier,
        cash_drawer_session: drawer_session,
        created_at: order.created_at
      )
    end

    def menu_item_for(line)
      return if line[:combo_id].present?

      MenuItem.find(line[:menu_item_id])
    end

    def combo_for(line)
      return if line[:combo_id].blank?

      Combo.find(line[:combo_id])
    end

    def location
      @location ||= Location.find_by(id: @payload[:location_id])
    end

    def workstation
      @workstation ||= Workstation.find_by(id: @payload[:workstation_id])
    end

    def order_type
      type = @payload[:order_type].to_s
      Order::ORDER_TYPES.include?(type) ? type : "pickup"
    end

    # Delivery has to be reachable: a phone to call and an address to go to, the
    # same two things the online POS will not submit a delivery without.
    def validate_delivery!
      raise ArgumentError, I18n.t("order.submit.errors.delivery_address_required") if @payload[:delivery_address].to_s.strip.blank?
      raise ArgumentError, I18n.t("customers.errors.email_or_phone_required") if customer_phone.blank?
    end

    def customer_phone
      @payload[:customer_phone].to_s.gsub(/[\s-]+/, "")
    end

    # Matched by phone exactly as the online POS does (primary or secondary), so a
    # regular who phones in during an outage is the same customer as the one in the
    # system, not a second record. Two registers can meet the same new number in the
    # same minute; the loser of that race finds the winner's record instead of failing
    # an order the customer has already paid for.
    def delivery_customer
      customer = Customer.find_by(phone: customer_phone) || Customer.find_by(phone_secondary: customer_phone)
      customer ||= create_customer
      remember_address(customer)
      customer
    end

    def create_customer
      Customer.transaction(requires_new: true) do
        Customer.create!(name: @payload[:customer_name].to_s.strip.presence, phone: customer_phone)
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      Customer.find_by(phone: customer_phone) || Customer.find_by(phone_secondary: customer_phone) || raise
    end

    # A new address goes on the customer's list (the first one becomes their default).
    def remember_address(customer)
      address = @payload[:delivery_address].to_s.strip
      return if customer.addresses.exists?(address: address)

      customer.addresses.create!(address: address)
    end

    # The cashier who rang the order owns it, and their drawer takes the cash —
    # that is what the till count at the end of their shift will be reconciled
    # against. Whoever happens to be signed in when the connection returns only
    # delivers it.
    def cashier
      @cashier ||= begin
        original = User.active.find_by(id: @payload[:user_id])
        original&.can_access_pos? ? original : @syncing_user
      end
    end

    def drawer_session
      @drawer_session ||= begin
        referenced = CashDrawerSession.open.find_by(id: @payload[:drawer_session_id], user_id: cashier.id)
        referenced || cashier.open_cash_drawer_session(location: location)
      end
    end

    def created_at
      raw = @payload[:created_at].presence
      time = raw && Time.zone.parse(raw.to_s)
      return Time.current if time.nil? || time > Time.current || time < MAX_AGE.ago

      time
    rescue ArgumentError
      Time.current
    end

    def failure(message)
      Result.new(success?: false, order: nil, duplicate: false, errors: [message])
    end
  end
end
