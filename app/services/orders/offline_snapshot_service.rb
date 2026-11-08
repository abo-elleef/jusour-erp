# frozen_string_literal: true

module Orders
  # Everything the offline register needs to keep selling with no internet: the
  # branch's menu with modifiers and live promo prices, the tax rates, which
  # printer takes which ticket, and where the print agent is.
  #
  # The browser keeps this in IndexedDB and refreshes it every time the POS is
  # online, so what it holds is at most a few minutes behind. Nothing here is a
  # secret the cashier's page does not already carry (the agent token is already
  # embedded in every POS page).
  class OfflineSnapshotService
    def self.call(user:, location:, workstation:, csrf_token:)
      new(user: user, location: location, workstation: workstation, csrf_token: csrf_token).call
    end

    def initialize(user:, location:, workstation:, csrf_token:)
      @user = user
      @location = location
      @workstation = workstation
      @csrf_token = csrf_token
    end

    def call
      {
        version: 1,
        generated_at: Time.current.iso8601,
        csrf_token: @csrf_token,
        user: { id: @user.id, name: @user.name },
        location: @location && { id: @location.id, name: @location.name, table_count: @location.table_count },
        workstation: @workstation && { id: @workstation.id, name: @workstation.name },
        drawer_session_id: drawer_session&.id,
        company: { receipt_name: @user.company.receipt_name },
        agent: agent,
        print: print_settings,
        menu: menu,
        tax_rates: tax_rates,
        printers: printers
      }
    end

    private

    def drawer_session
      return @drawer_session if defined?(@drawer_session)

      @drawer_session = @user.open_cash_drawer_session(location: @location)
    end

    def agent
      {
        url: Printing::Config.agent_url,
        token: Printing::Config.agent_token,
        client_routing: Printing::Config.client_routing?
      }
    end

    def print_settings
      {
        rtl: Printing::Escpos::Charset.resolve[:rtl] ? true : false,
        footer: Printing::Config.receipt_footer_text.presence || I18n.t("printing.receipt.thank_you")
      }
    end

    def menu
      result = Menus::ForLocation.call(location: @location)

      {
        categories: result.categories.map { |category| { id: category.id, name: category.name } },
        items: result.menu_items.map { |item| item_json(item, result.promos_by_item_id[item.id]) },
        combos: result.combos.includes(:combo_items).map { |combo| combo_json(combo) }
      }
    end

    def item_json(item, promo)
      {
        id: item.id,
        name: item.name,
        category_id: item.category_id,
        price_cents: item.price_cents_at(@location),
        tax_category: item.tax_category.presence || "food",
        promo: promo && {
          id: promo.promo.id,
          label: promo.label,
          discount_cents: promo.discount_cents
        },
        modifier_groups: item.modifier_groups.map { |group| group_json(group) }
      }
    end

    def group_json(group)
      {
        id: group.id,
        name: group.name,
        required: group.required ? true : false,
        multi_select: group.multi_select ? true : false,
        modifiers: group.modifiers.map do |modifier|
          { id: modifier.id, name: modifier.name, price_adjustment_cents: modifier.price_adjustment_cents }
        end
      }
    end

    def combo_json(combo)
      {
        id: combo.id,
        name: combo.name,
        price_cents: combo.price_cents,
        menu_item_ids: combo.combo_items.map(&:menu_item_id)
      }
    end

    # Rates travel as exact decimal strings: the browser does the arithmetic in
    # integers, so a rate like 0.145 never passes through a float.
    def tax_rates
      TaxRate.active.map { |rate| { tax_category: rate.tax_category, rate: rate.rate.to_d.to_s("F") } }
    end

    def printers
      return { receipt: nil, expo: nil, stations: [] } if @location.blank?

      {
        receipt: printer_json(receipt_printer),
        expo: printer_json(Printer.default_for("expo", location: @location)),
        stations: Printer.production_stations.for_location(@location).includes(:printer_menu_items).map { |p| printer_json(p) }
      }
    end

    def receipt_printer
      from_workstation = @workstation&.receipt_printer
      return from_workstation if from_workstation&.active?

      Printer.default_for("receipt", location: @location)
    end

    def printer_json(printer)
      return if printer.blank?

      {
        id: printer.id,
        name: printer.name,
        type: printer.printer_type,
        station: printer.station.presence || printer.name,
        connection: printer.connection_type,
        host: printer.host,
        port: printer.port || Printing::Drivers::Network::DEFAULT_PORT,
        paper_width: printer.paper_width,
        menu_item_ids: printer.printer_menu_items.map(&:menu_item_id)
      }
    end
  end
end
