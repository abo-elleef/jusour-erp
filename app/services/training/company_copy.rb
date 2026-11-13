# frozen_string_literal: true

module Training
  # Copies one company's CATALOGUE into a brand-new company, so new staff can
  # practise on the real menu, ingredients and suppliers without being able to
  # see — or damage — anything real.
  #
  # COPIED: the things you configure. Units, roles, attendance statuses,
  # locations, ingredients (and their categories, alternate units, per-location
  # par levels), the menu, modifiers, combos, suppliers, treasury structure,
  # expense/income categories, tax rates, printers, workstations, manufacturing
  # and transfer templates, discounts, promos, overtime rules.
  #
  # NOT COPIED: the things that happened, and the people. No orders, payments,
  # journal entries, stock movements, vendor invoices, payroll or customers —
  # and no users, so no salaries. Every balance lands at zero.
  #
  # The source company is only ever read from. Everything is written inside one
  # transaction, so a failure half-way leaves no partial company behind.
  #
  #   Training::CompanyCopy.call(source_slug: "saqr-local", slug: "training-01")
  class CompanyCopy
    DEFAULT_PASSWORD = "changeme123"

    # Practice stock, so the sandbox can actually exercise transfers,
    # manufacturing and selling on day one. Each active ingredient is stocked to
    # this multiple of its reorder threshold at each active location, with a
    # matching batch so FIFO costing stays consistent with on-hand.
    OPENING_STOCK_MULTIPLE = 4
    OPENING_STOCK_MINIMUM = 20

    # Copied verbatim would hand the training company the live print agent's
    # credential, and its own name.
    SETTING_EXCLUSIONS = %w[print_agent_token restaurant_name].freeze

    Result = Struct.new(:company, :owner_email, :password, :mates, :counts, :skipped, keyword_init: true)

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(source_slug:, slug:, name: nil, password: nil, mates: [], mate_role: "manager",
                   opening_stock: true)
      @source_slug = source_slug.to_s.strip
      @slug = slug.to_s.strip
      @name = name.presence
      @password = password.presence || DEFAULT_PASSWORD
      @mates = Array(mates).map { |m| m.to_s.strip.downcase }.reject(&:blank?).uniq
      @mate_role = mate_role.to_s.presence || "manager"
      @opening_stock = opening_stock
      @map = Hash.new { |h, k| h[k] = {} }
      @counts = Hash.new(0)
      @skipped = []
      @unit_ids_by_ingredient = {}
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        create_company!
        Current.company = @company

        copy_settings!
        copy_units!
        copy_roles!
        copy_attendance_statuses!
        copy_locations!
        copy_ingredients!
        copy_menu!
        copy_modifiers!
        copy_combos!
        copy_price_tiers!
        copy_suppliers_and_treasuries!
        copy_accounting_lists!
        copy_printing!
        copy_location_menu_items!
        copy_ingredient_locations!
        copy_templates!
        copy_promotions!
        create_users!
        seed_opening_stock! if @opening_stock
      end

      Result.new(
        company: @company,
        owner_email: owner_email,
        password: @password,
        mates: @mates.map { |m| mate_email(m) },
        counts: @counts,
        skipped: @skipped
      )
    ensure
      Current.reset
    end

    private

    attr_reader :source

    def validate!
      raise ArgumentError, "SOURCE_SLUG is required" if @source_slug.blank?
      raise ArgumentError, "SLUG is required" if @slug.blank?
      raise ArgumentError, "SLUG must match [a-z0-9-]+" unless @slug.match?(/\A[a-z0-9\-]+\z/)
      raise ArgumentError, "SLUG must differ from SOURCE_SLUG" if @slug == @source_slug
      raise ArgumentError, "Company slug=#{@slug} already exists. Pick another SLUG." if Company.unscoped.exists?(slug: @slug)
      unless User::ROLES.include?(@mate_role)
        raise ArgumentError, "MATE_ROLE=#{@mate_role} is not one of: #{User::ROLES.join(', ')}"
      end

      @source = Company.unscoped.find_by(slug: @source_slug)
      raise ArgumentError, "No company with slug=#{@source_slug}" if @source.nil?
    end

    def owner_email
      "owner@#{@slug}.training"
    end

    def mate_email(handle)
      "#{handle}@#{@slug}.training"
    end

    # ---------------------------------------------------------------- helpers

    # Source rows for a tenant-scoped model. `unscoped` because the default
    # scope would otherwise pin reads to the company being written to.
    def from_source(model)
      model.unscoped.where(company_id: source.id).order(:created_at, :id)
    end

    # Child rows, which carry no company_id of their own and are reached through
    # whichever parent ids we have already copied.
    def children(model, **parent_ids)
      model.unscoped.where(**parent_ids).order(:created_at, :id)
    end

    def attrs_of(record, except: [])
      record.attributes.except("id", "company_id", "created_at", "updated_at", *except.map(&:to_s))
    end

    # Create the copy, remember old id -> new id, and count it.
    #
    # A row the source itself can no longer re-save — a stale unit left behind
    # when an ingredient's base unit was changed, say — is reported and stepped
    # over rather than aborting the whole company. Its children then drop out on
    # their own, because the id lookup returns nil. Every skip is listed at the
    # end, so nothing disappears quietly.
    def track!(key, src, record)
      record.company = @company if record.respond_to?(:company=)
      record.save!
      @map[key][src.id] = record.id
      @counts[key] += 1
      record
    rescue ActiveRecord::RecordInvalid => e
      skip!(key, src, e.record.errors.full_messages.to_sentence)
      nil
    end

    def skip!(key, src, reason)
      @skipped << {
        model: key,
        id: src.id,
        label: skip_label(src),
        reason: reason
      }
      @counts[:"#{key}_skipped"] += 1
      nil
    end

    # A bare uuid tells the operator nothing about what to go and fix, so name the
    # row by its ingredient and the parent it hangs off.
    #
    # Every lookup is unscoped and by id: we are running with Current.company set
    # to the company being *written*, so reading a source row's associations the
    # ordinary way would come back empty.
    PARENT_LOOKUPS = {
      "menu_item_id" => MenuItem,
      "stock_transfer_template_id" => StockTransferTemplate,
      "manufacturing_template_id" => ManufacturingTemplate
    }.freeze

    def skip_label(src)
      return src.name if src.try(:name).present?

      parts = []
      if src.has_attribute?("ingredient_id")
        parts << Ingredient.unscoped.find_by(id: src.ingredient_id)&.name
      end
      PARENT_LOOKUPS.each do |column, model|
        next unless src.has_attribute?(column)

        parent = model.unscoped.find_by(id: src.public_send(column))
        parts << "in #{parent.name}" if parent
      end
      if src.has_attribute?("unit_id") && src.unit_id.present?
        parts << "unit #{Unit.unscoped.find_by(id: src.unit_id)&.name}"
      end

      parts.compact.join(" — ").presence || src.try(:code).presence || src.id
    end

    def mapped(key, old_id)
      old_id.nil? ? nil : @map[key][old_id]
    end

    # True when the unit is still one the ingredient actually offers. Rows that
    # fail this are already broken in the source — the ingredient's base unit was
    # changed after the row was written — and would fail validation on save.
    def unit_available?(new_ingredient_id, new_unit_id)
      return false if new_ingredient_id.nil?
      return true if new_unit_id.nil?

      ids = @unit_ids_by_ingredient[new_ingredient_id] ||= begin
        ingredient = Ingredient.unscoped.find_by(id: new_ingredient_id)
        ingredient ? ingredient.available_unit_ids : []
      end
      ids.include?(new_unit_id)
    end

    # ---------------------------------------------------------------- company

    def create_company!
      @company = Company.create!(
        name: @name || "#{source.name} — Training",
        slug: @slug,
        timezone: source.timezone,
        currency: source.currency,
        locale: source.locale,
        business_type: source.business_type,
        feature_overrides: source.feature_overrides,
        active: true
      )
      @counts[:companies] = 1
    end

    def copy_settings!
      src = CompanySetting.unscoped.find_by(company_id: source.id)
      row = CompanySetting.unscoped.find_or_initialize_by(company_id: @company.id)
      row.assign_attributes(attrs_of(src, except: SETTING_EXCLUSIONS)) if src
      row.restaurant_name = @company.name
      row.save!
      @counts[:settings] = 1
    end

    # ------------------------------------------------------- reference tables

    # Company creation already seeded the built-in units, so match on name and
    # only create what the source added on top.
    def copy_units!
      existing = Unit.unscoped.where(company_id: @company.id).index_by { |u| u.name.to_s.downcase }

      from_source(Unit).each do |src|
        found = existing[src.name.to_s.downcase]
        if found
          @map[:units][src.id] = found.id
          next
        end
        track!(:units, src, Unit.new(attrs_of(src)))
      end
    end

    # Built-in roles are seeded on create; carry the source's *edited*
    # permissions onto them, since a customised role is configuration.
    def copy_roles!
      existing = Role.unscoped.where(company_id: @company.id).index_by(&:key)

      from_source(Role).each do |src|
        found = existing[src.key]
        if found
          found.update!(name: src.name, permissions: src.permissions)
          @map[:roles][src.id] = found.id
          next
        end
        track!(:roles, src, Role.new(attrs_of(src)))
      end
    end

    def copy_attendance_statuses!
      existing = AttendanceStatus.unscoped.where(company_id: @company.id).index_by(&:code)

      from_source(AttendanceStatus).each do |src|
        found = existing[src.code]
        if found
          @map[:attendance_statuses][src.id] = found.id
          next
        end
        track!(:attendance_statuses, src, AttendanceStatus.new(attrs_of(src)))
      end
    end

    def copy_locations!
      from_source(Location).each do |src|
        track!(:locations, src, Location.new(attrs_of(src)))
      end
    end

    # ------------------------------------------------------------- ingredients

    def copy_ingredients!
      from_source(IngredientCategory).each do |src|
        track!(:ingredient_categories, src, IngredientCategory.new(attrs_of(src)))
      end

      from_source(Ingredient).each do |src|
        record = Ingredient.new(attrs_of(src, except: %w[ingredient_category_id unit_id quantity_on_hand]))
        record.ingredient_category_id = mapped(:ingredient_categories, src.ingredient_category_id)
        record.unit_id = mapped(:units, src.unit_id)
        # On-hand is a balance, and it is seeded separately (with matching
        # batches) rather than copied — a copied quantity with no batch behind it
        # would break FIFO costing on the first sale.
        record.quantity_on_hand = 0
        track!(:ingredients, src, record)
      end

      from_source(IngredientUnit).each do |src|
        record = IngredientUnit.new(attrs_of(src, except: %w[ingredient_id unit_id]))
        record.ingredient_id = mapped(:ingredients, src.ingredient_id)
        record.unit_id = mapped(:units, src.unit_id)
        track!(:ingredient_units, src, record)
      end
    end

    # Par levels and maximums are configuration and worth having; the quantity
    # sitting on the shelf is not.
    def copy_ingredient_locations!
      children(IngredientLocation, ingredient_id: @map[:ingredients].keys).each do |src|
        location_id = mapped(:locations, src.location_id)
        ingredient_id = mapped(:ingredients, src.ingredient_id)
        next if location_id.nil? || ingredient_id.nil?

        record = IngredientLocation.new(attrs_of(src, except: %w[ingredient_id location_id quantity_on_hand]))
        record.ingredient_id = ingredient_id
        record.location_id = location_id
        record.quantity_on_hand = 0
        track!(:ingredient_locations, src, record)
      end
    end

    # -------------------------------------------------------------------- menu

    def copy_menu!
      from_source(Category).each do |src|
        track!(:categories, src, Category.new(attrs_of(src)))
      end

      from_source(MenuItem).each do |src|
        record = MenuItem.new(attrs_of(src, except: %w[category_id]))
        record.category_id = mapped(:categories, src.category_id)
        track!(:menu_items, src, record)
      end

      children(Recipe, menu_item_id: @map[:menu_items].keys).each do |src|
        record = Recipe.new(attrs_of(src, except: %w[menu_item_id ingredient_id unit_id]))
        record.menu_item_id = mapped(:menu_items, src.menu_item_id)
        record.ingredient_id = mapped(:ingredients, src.ingredient_id)
        record.unit_id = mapped(:units, src.unit_id)
        next if record.menu_item_id.nil? || record.ingredient_id.nil?
        next skip!(:recipes, src, "unit is no longer one of the ingredient's units") unless
          unit_available?(record.ingredient_id, record.unit_id)

        track!(:recipes, src, record)
      end
    end

    def copy_modifiers!
      from_source(ModifierGroup).each do |src|
        track!(:modifier_groups, src, ModifierGroup.new(attrs_of(src)))
      end

      from_source(Modifier).each do |src|
        record = Modifier.new(attrs_of(src, except: %w[modifier_group_id]))
        record.modifier_group_id = mapped(:modifier_groups, src.modifier_group_id)
        track!(:modifiers, src, record)
      end

      children(MenuItemModifierGroup, menu_item_id: @map[:menu_items].keys).each do |src|
        record = MenuItemModifierGroup.new(attrs_of(src, except: %w[menu_item_id modifier_group_id]))
        record.menu_item_id = mapped(:menu_items, src.menu_item_id)
        record.modifier_group_id = mapped(:modifier_groups, src.modifier_group_id)
        next if record.modifier_group_id.nil?

        track!(:menu_item_modifier_groups, src, record)
      end

      from_source(ModifierRecipe).each do |src|
        record = ModifierRecipe.new(attrs_of(src, except: %w[modifier_id ingredient_id unit_id]))
        record.modifier_id = mapped(:modifiers, src.modifier_id)
        record.ingredient_id = mapped(:ingredients, src.ingredient_id)
        record.unit_id = mapped(:units, src.unit_id)
        next if record.modifier_id.nil? || record.ingredient_id.nil?
        next skip!(:modifier_recipes, src, "unit is no longer one of the ingredient's units") unless
          unit_available?(record.ingredient_id, record.unit_id)

        track!(:modifier_recipes, src, record)
      end
    end

    def copy_combos!
      from_source(Combo).each do |src|
        track!(:combos, src, Combo.new(attrs_of(src)))
      end

      children(ComboItem, combo_id: @map[:combos].keys).each do |src|
        record = ComboItem.new(attrs_of(src, except: %w[combo_id menu_item_id]))
        record.combo_id = mapped(:combos, src.combo_id)
        record.menu_item_id = mapped(:menu_items, src.menu_item_id)
        next if record.menu_item_id.nil?

        track!(:combo_items, src, record)
      end
    end

    def copy_price_tiers!
      from_source(PriceTier).each do |src|
        track!(:price_tiers, src, PriceTier.new(attrs_of(src)))
      end
    end

    # ------------------------------------------------- suppliers + treasuries

    # Supplier and Treasury point at each other (a supplier's paying treasury, a
    # treasury's supplier AP sub-ledger), so suppliers are created without their
    # treasury and wired up once the treasuries exist.
    def copy_suppliers_and_treasuries!
      # Creating a supplier fires `ensure_ap_treasury!`, which builds its AP
      # sub-ledger for us and links it back. So the supplier's own AP treasury is
      # never copied — it is mapped onto the one the hook just made, and the
      # treasury pass below skips it to avoid a second, orphaned copy.
      from_source(Supplier).each do |src|
        record = track!(:suppliers, src, Supplier.new(attrs_of(src, except: %w[treasury_id])))
        auto_ap_id = record.reload.treasury_id
        next if auto_ap_id.blank?

        @counts[:treasuries] += 1
        @map[:treasuries][src.treasury_id] = auto_ap_id if src.treasury_id.present?
        # Also map the sub-ledger reached from the treasury side, when the source
        # pair disagree about which treasury belongs to this supplier.
        source_ap = Treasury.unscoped.find_by(company_id: source.id, supplier_id: src.id)
        @map[:treasuries][source_ap.id] ||= auto_ap_id if source_ap
      end

      # A staff member's personal cash drawer belongs to a person we are not
      # copying; each training user gets their own on creation instead.
      personal_drawer_ids = User.unscoped.where(company_id: source.id).pluck(:assigned_treasury_id).compact.uniq

      from_source(Treasury).each do |src|
        next if personal_drawer_ids.include?(src.id)
        # An AR sub-ledger for a customer, and customers are not copied.
        next if src.customer_id.present?
        # Already created by the supplier hook above.
        next if @map[:treasuries].key?(src.id)

        record = Treasury.new(attrs_of(src, except: %w[supplier_id customer_id balance_cents opening_balance_cents]))
        record.supplier_id = mapped(:suppliers, src.supplier_id)
        record.balance_cents = 0
        record.opening_balance_cents = 0
        track!(:treasuries, src, record)
      end

      children(SupplierIngredient, supplier_id: @map[:suppliers].keys).each do |src|
        record = SupplierIngredient.new(attrs_of(src, except: %w[supplier_id ingredient_id]))
        record.supplier_id = mapped(:suppliers, src.supplier_id)
        record.ingredient_id = mapped(:ingredients, src.ingredient_id)
        next if record.ingredient_id.nil?

        track!(:supplier_ingredients, src, record)
      end
    end

    # The chart of accounts itself is derived in code, so only the editable
    # category lists and rates need carrying over.
    def copy_accounting_lists!
      from_source(ExpenseCategory).each do |src|
        track!(:expense_categories, src, ExpenseCategory.new(attrs_of(src)))
      end

      from_source(IncomeCategory).each do |src|
        track!(:income_categories, src, IncomeCategory.new(attrs_of(src)))
      end

      from_source(TaxRate).each do |src|
        track!(:tax_rates, src, TaxRate.new(attrs_of(src)))
      end

      from_source(OvertimeRule).each do |src|
        track!(:overtime_rules, src, OvertimeRule.new(attrs_of(src)))
      end

      from_source(PaymentMethodTreasury).each do |src|
        record = PaymentMethodTreasury.new(attrs_of(src, except: %w[treasury_id]))
        record.treasury_id = mapped(:treasuries, src.treasury_id)
        next if record.treasury_id.nil?

        track!(:payment_method_treasuries, src, record)
      end
    end

    # ---------------------------------------------------------------- printing

    def copy_printing!
      from_source(Printer).each do |src|
        record = Printer.new(attrs_of(src, except: %w[location_id]))
        record.location_id = mapped(:locations, src.location_id)
        track!(:printers, src, record)
      end

      children(PrinterMenuItem, printer_id: @map[:printers].keys).each do |src|
        record = PrinterMenuItem.new(attrs_of(src, except: %w[printer_id menu_item_id]))
        record.printer_id = mapped(:printers, src.printer_id)
        record.menu_item_id = mapped(:menu_items, src.menu_item_id)
        next if record.menu_item_id.nil?

        track!(:printer_menu_items, src, record)
      end

      from_source(Workstation).each do |src|
        record = Workstation.new(attrs_of(src, except: %w[location_id receipt_printer_id]))
        record.location_id = mapped(:locations, src.location_id)
        record.receipt_printer_id = mapped(:printers, src.receipt_printer_id)
        track!(:workstations, src, record)
      end
    end

    def copy_location_menu_items!
      children(LocationMenuItem, location_id: @map[:locations].keys).each do |src|
        record = LocationMenuItem.new(attrs_of(src, except: %w[location_id menu_item_id]))
        record.location_id = mapped(:locations, src.location_id)
        record.menu_item_id = mapped(:menu_items, src.menu_item_id)
        next if record.menu_item_id.nil?

        track!(:location_menu_items, src, record)
      end
    end

    # --------------------------------------------------------------- templates

    # Both template kinds refuse to save active with no lines, so each is built
    # with its lines nested rather than saved and then filled.
    def copy_templates!
      from_source(ManufacturingTemplate).each do |src|
        record = ManufacturingTemplate.new(
          attrs_of(src, except: %w[output_ingredient_id yield_unit_id main_ingredient_id])
        )
        record.output_ingredient_id = mapped(:ingredients, src.output_ingredient_id)
        record.yield_unit_id = mapped(:units, src.yield_unit_id)
        record.main_ingredient_id = mapped(:ingredients, src.main_ingredient_id)
        next if record.output_ingredient_id.nil?

        children(ManufacturingTemplateLine, manufacturing_template_id: src.id).each do |line|
          ingredient_id = mapped(:ingredients, line.ingredient_id)
          next if ingredient_id.nil?
          next skip!(:manufacturing_template_lines, line, "unit is no longer one of the ingredient's units") unless
            unit_available?(ingredient_id, mapped(:units, line.unit_id))

          record.manufacturing_template_lines.build(
            attrs_of(line, except: %w[manufacturing_template_id ingredient_id unit_id]).merge(
              "ingredient_id" => ingredient_id,
              "unit_id" => mapped(:units, line.unit_id)
            )
          )
          @counts[:manufacturing_template_lines] += 1
        end

        track!(:manufacturing_templates, src, record)
      end

      from_source(StockTransferTemplate).each do |src|
        record = StockTransferTemplate.new(
          attrs_of(src, except: %w[default_from_location_id default_to_location_id])
        )
        record.default_from_location_id = mapped(:locations, src.default_from_location_id)
        record.default_to_location_id = mapped(:locations, src.default_to_location_id)

        children(StockTransferTemplateLine, stock_transfer_template_id: src.id).each do |line|
          ingredient_id = mapped(:ingredients, line.ingredient_id)
          next if ingredient_id.nil?
          next skip!(:stock_transfer_template_lines, line, "unit is no longer one of the ingredient's units") unless
            unit_available?(ingredient_id, mapped(:units, line.unit_id))

          record.stock_transfer_template_lines.build(
            attrs_of(line, except: %w[stock_transfer_template_id ingredient_id unit_id]).merge(
              "ingredient_id" => ingredient_id,
              "unit_id" => mapped(:units, line.unit_id)
            )
          )
          @counts[:stock_transfer_template_lines] += 1
        end

        track!(:stock_transfer_templates, src, record)
      end
    end

    def copy_promotions!
      from_source(DiscountRule).each do |src|
        record = DiscountRule.new(attrs_of(src, except: %w[applies_to_id]))
        # applies_to says which table applies_to_id points into; an order-wide
        # rule has no target at all.
        record.applies_to_id = case src.applies_to
                               when "item" then mapped(:menu_items, src.applies_to_id)
                               when "category" then mapped(:categories, src.applies_to_id)
                               end
        track!(:discount_rules, src, record)
      end

      from_source(MenuPromo).each do |src|
        record = MenuPromo.new(attrs_of(src, except: %w[menu_item_id location_id]))
        record.menu_item_id = mapped(:menu_items, src.menu_item_id)
        record.location_id = mapped(:locations, src.location_id)
        next if src.menu_item_id.present? && record.menu_item_id.nil?

        track!(:menu_promos, src, record)
      end
    end

    # ------------------------------------------------------------------- users

    # No user is copied — the source's people carry salaries and payroll. The
    # training company gets an owner (which super-admin "impersonate" needs) plus
    # one account per new mate.
    def create_users!
      @company.reload

      @owner = User.create!(
        email: owner_email,
        name: "Training Owner",
        role: "owner",
        password: @password,
        password_confirmation: @password,
        monthly_salary_cents: 0,
        all_locations: true
      )
      @counts[:users] += 1

      @mates.each do |handle|
        User.create!(
          email: mate_email(handle),
          name: handle.titleize,
          role: @mate_role,
          password: @password,
          password_confirmation: @password,
          monthly_salary_cents: 0,
          all_locations: true
        )
        @counts[:users] += 1
      end
    end

    # ----------------------------------------------------------- opening stock

    # Without stock the sandbox cannot transfer, manufacture or sell anything, so
    # each active ingredient is given a round practice quantity at each active
    # location, backed by a real batch so costing lines up with on-hand.
    def seed_opening_stock!
      locations = Location.unscoped.where(company_id: @company.id, active: true).to_a
      return if locations.empty?

      Ingredient.unscoped.where(company_id: @company.id, active: true).find_each do |ingredient|
        per_location = [(ingredient.reorder_threshold.to_d * OPENING_STOCK_MULTIPLE), OPENING_STOCK_MINIMUM.to_d].max

        locations.each do |location|
          StockBatch.create!(
            ingredient_id: ingredient.id,
            location_id: location.id,
            quantity_received: per_location,
            quantity_remaining: per_location,
            cost_per_unit_cents: ingredient.cost_per_unit_cents.to_i,
            received_on: Date.current,
            batch_reference: "TRAINING-OPENING"
          )
          @counts[:stock_batches] += 1

          row = IngredientLocation.unscoped.find_or_initialize_by(
            ingredient_id: ingredient.id, location_id: location.id
          )
          row.quantity_on_hand = per_location
          row.save!
        end

        ingredient.update_columns(quantity_on_hand: per_location * locations.size)
      end
    end
  end
end
