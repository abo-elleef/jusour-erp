# frozen_string_literal: true

module Demo
  # Bootstraps an isolated fried-chicken demo company for client demos.
  # Does not modify other tenants. Safe to run on production with a new DEMO_SLUG.
  #
  #   Demo::FriedChickenBootstrap.call(slug: "demo-fried-chicken")
  class FriedChickenBootstrap
    DEFAULT_PASSWORD = "changeme123"
    INGREDIENT_CATEGORIES = [
      "Proteins", "Produce", "Dairy", "Dry Goods", "Sauces & Condiments", "Packaging"
    ].freeze

    INGREDIENTS = [
      { name: "Chicken Thighs", unit: "kg", category: "Proteins", reorder_threshold: 5, cost_per_unit_cents: 450, qty: 12 },
      { name: "Beef Patties (4oz)", unit: "pieces", category: "Proteins", reorder_threshold: 50, cost_per_unit_cents: 175, qty: 120 },
      { name: "Burger Buns", unit: "pieces", category: "Dry Goods", reorder_threshold: 100, cost_per_unit_cents: 30, qty: 200 },
      { name: "Chicken Buns", unit: "pieces", category: "Dry Goods", reorder_threshold: 100, cost_per_unit_cents: 28, qty: 150 },
      { name: "Shredded Lettuce", unit: "kg", category: "Produce", reorder_threshold: 2, cost_per_unit_cents: 180, qty: 4 },
      { name: "Tomatoes", unit: "kg", category: "Produce", reorder_threshold: 2, cost_per_unit_cents: 220, qty: 5 },
      { name: "American Cheese", unit: "pieces", category: "Dairy", reorder_threshold: 100, cost_per_unit_cents: 20, qty: 250 },
      { name: "Buttermilk", unit: "liters", category: "Dairy", reorder_threshold: 3, cost_per_unit_cents: 150, qty: 8 },
      { name: "Flour", unit: "kg", category: "Dry Goods", reorder_threshold: 10, cost_per_unit_cents: 80, qty: 25 },
      { name: "House Sauce", unit: "liters", category: "Sauces & Condiments", reorder_threshold: 2, cost_per_unit_cents: 300, qty: 6 },
      { name: "Fry Oil", unit: "liters", category: "Dry Goods", reorder_threshold: 10, cost_per_unit_cents: 200, qty: 20 },
      { name: "Takeout Boxes", unit: "pieces", category: "Packaging", reorder_threshold: 200, cost_per_unit_cents: 15, qty: 500 }
    ].freeze

    EXPENSE_CATEGORIES = [
      { name: "COGS", category_type: "cogs", system_managed: true, position: 1 },
      { name: "Vendor purchases", category_type: "other", system_managed: true, position: 0 },
      { name: "Goods delivery", category_type: "other", system_managed: true, position: 0 },
      { name: "Labor", category_type: "labor", system_managed: true, position: 2 },
      { name: "Rent", category_type: "rent", system_managed: false, position: 3 },
      { name: "Utilities", category_type: "utilities", system_managed: false, position: 4 },
      { name: "Marketing", category_type: "marketing", system_managed: false, position: 5 },
      { name: "Maintenance", category_type: "maintenance", system_managed: false, position: 6 },
      { name: "Other", category_type: "other", system_managed: false, position: 7 }
    ].freeze

    INCOME_CATEGORIES = [
      { name: "POS Sales", category_type: "sales", system_managed: true, position: 1 },
      { name: "Catering", category_type: "catering", system_managed: false, position: 2 },
      { name: "Delivery Fees", category_type: "delivery", system_managed: false, position: 3 },
      { name: "Services", category_type: "services", system_managed: false, position: 4 },
      { name: "Other Income", category_type: "other", system_managed: false, position: 5 }
    ].freeze

    TREASURIES = [
      { name: "Main Safe", treasury_type: "safe", opening_balance_cents: 500_000, balance_cents: 500_000, is_default: true, position: 1 },
      { name: "Front Register", treasury_type: "cash_drawer", opening_balance_cents: 50_000, balance_cents: 50_000, position: 2 },
      { name: "Bank Account", treasury_type: "bank", opening_balance_cents: 1_000_000, balance_cents: 1_000_000, position: 3 }
    ].freeze

    Result = Struct.new(:company, :owner_email, :password, keyword_init: true)

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(slug:, name: nil, password: nil)
      @slug = slug.to_s.strip
      @name = name.presence || "Demo Fried Chicken"
      @password = password.presence || DEFAULT_PASSWORD
    end

    def call
      validate_slug!
      require Rails.root.join("db/seeds/saqr_fried_chicken_menu")

      company = nil
      ActiveRecord::Base.transaction do
        company = Company.create!(
          name: @name,
          slug: @slug,
          timezone: "Africa/Cairo",
          currency: "EGP",
          locale: "ar",
          active: true
        )

        Current.company = company

        seed_settings!
        seed_users!
        seed_tax_rates!
        SaqrFriedChickenMenu.seed!(company: company)
        seed_promos!
        seed_inventory!
        seed_accounting!
        main_branch = seed_location_and_printers!
        SaqrFriedChickenMenu.seed_location_menu!(location: main_branch)
      end

      Result.new(
        company: company,
        owner_email: owner_email,
        password: @password
      )
    ensure
      Current.reset
    end

    private

    def validate_slug!
      raise ArgumentError, "slug is required" if @slug.blank?
      raise ArgumentError, "slug must match [a-z0-9-]+" unless @slug.match?(/\A[a-z0-9\-]+\z/)
      return unless Company.unscoped.exists?(slug: @slug)

      raise ArgumentError, "Company slug=#{@slug} already exists. Pick another DEMO_SLUG."
    end

    def owner_email
      "owner@#{@slug}.demo"
    end

    def seed_settings!
      Setting.set("restaurant_name", @name)
      Setting.set("loyalty_earn_rate", "1")
      Setting.set("loyalty_redeem_threshold", "100")
      Setting.set("loyalty_redeem_value_cents", "500")
      Setting.set("print_routing", Printing::Config::ROUTING_CLIENT) if Setting.get("print_routing").blank?
      Setting.set("print_agent_port", Printing::Config::DEFAULT_AGENT_PORT) if Setting.get("print_agent_port").blank?
    end

    def seed_users!
      {
        owner_email => ["Demo Owner", "owner", 0],
        "manager@#{@slug}.demo" => ["Demo Manager", "manager", 450_000],
        "cashier@#{@slug}.demo" => ["Demo Cashier", "cashier", 300_000],
        "kitchen@#{@slug}.demo" => ["Demo Kitchen", "kitchen", 320_000]
      }.each do |email, (uname, role, salary)|
        User.create!(
          email: email,
          name: uname,
          role: role,
          password: @password,
          password_confirmation: @password,
          monthly_salary_cents: salary
        )
      end
    end

    def seed_tax_rates!
      TaxRate.create!(name: "State Food Tax", tax_category: "food", rate: 0.08, active: true)
      TaxRate.create!(name: "Beverage Tax", tax_category: "beverage", rate: 0.085, active: true)
    end

    def seed_promos!
      DiscountRule.create!(
        code: "WELCOME10",
        name: "Welcome 10% Off",
        discount_type: "percentage",
        discount_value: 10,
        applies_to: "order",
        minimum_order_cents: 1000,
        active: true
      )
      GiftCard.create!(code: "GIFT100", balance_cents: 10_000, active: true)
    end

    def seed_inventory!
      INGREDIENT_CATEGORIES.each_with_index do |name, i|
        IngredientCategory.find_or_create_by!(name: name) { |c| c.position = i }
      end

      INGREDIENTS.each do |attrs|
        cat = IngredientCategory.find_by!(name: attrs[:category])
        ing = Ingredient.find_or_create_by!(name: attrs[:name]) do |i|
          i.ingredient_category = cat
          i.unit = attrs[:unit]
          i.reorder_threshold = attrs[:reorder_threshold]
          i.cost_per_unit_cents = attrs[:cost_per_unit_cents]
          i.quantity_on_hand = attrs[:qty]
        end
        StockBatch.find_or_create_by!(ingredient: ing, batch_reference: "DEMO-#{ing.name.parameterize}") do |b|
          b.quantity_received = ing.quantity_on_hand
          b.quantity_remaining = ing.quantity_on_hand
          b.cost_per_unit_cents = ing.cost_per_unit_cents
          b.received_on = Date.current
          b.expires_on = 30.days.from_now.to_date
        end
      end

      supplier = Supplier.find_or_create_by!(name: "Metro Food Distributors") do |s|
        s.contact_name = "John Metro"
        s.email = "orders@metrofood.example.com"
        s.phone = "555-0100"
        s.lead_time_days = 2
      end

      Ingredient.active.find_each do |ing|
        SupplierIngredient.find_or_create_by!(supplier: supplier, ingredient: ing) do |si|
          si.price_cents = ing.cost_per_unit_cents
          si.preferred = true
        end
      end

      seed_prep_template!
    end

    def seed_prep_template!
      chicken = Ingredient.find_by(name: "Chicken Thighs")
      buttermilk = Ingredient.find_by(name: "Buttermilk")
      proteins_cat = IngredientCategory.find_by(name: "Proteins")
      return unless chicken && buttermilk && proteins_cat

      marinated = Ingredient.find_or_create_by!(name: "Marinated Chicken (Prep)") do |i|
        i.ingredient_category = proteins_cat
        i.unit = "kg"
        i.reorder_threshold = 3
        i.cost_per_unit_cents = 0
        i.quantity_on_hand = 0
      end

      template = ManufacturingTemplate.find_or_create_by!(name: "Marinate Chicken Batch") do |t|
        t.output_ingredient = marinated
        t.yield_quantity = 5
        t.position = 1
        t.active = false
      end
      ManufacturingTemplateLine.find_or_create_by!(manufacturing_template: template, ingredient: chicken) do |l|
        l.quantity_used = 4
      end
      ManufacturingTemplateLine.find_or_create_by!(manufacturing_template: template, ingredient: buttermilk) do |l|
        l.quantity_used = 2
      end
      template.update!(active: true) if template.manufacturing_template_lines.any?
    end

    def seed_accounting!
      EXPENSE_CATEGORIES.each do |attrs|
        ExpenseCategory.find_or_create_by!(name: attrs[:name]) { |e| e.assign_attributes(attrs) }
      end

      INCOME_CATEGORIES.each do |attrs|
        IncomeCategory.find_or_create_by!(name: attrs[:name]) { |e| e.assign_attributes(attrs) }
      end

      TREASURIES.each do |attrs|
        Treasury.find_or_create_by!(name: attrs[:name]) { |t| t.assign_attributes(attrs) }
      end

      OvertimeRule.find_or_create_by!(name: "Federal Standard") do |r|
        r.weekly_threshold_hours = 40.0
        r.ot_multiplier = 1.5
        r.active = true
      end

      current_month = Date.current
      ExpenseCategory.where(system_managed: false).find_each do |cat|
        Budget.find_or_create_by!(expense_category: cat, year: current_month.year, month: current_month.month) do |b|
          b.amount_cents = 200_000
        end
      end
    end

    def seed_location_and_printers!
      main_branch = Location.find_or_create_by!(name: "Main Branch") do |l|
        l.location_type = "branch"
        l.active = true
        l.position = 0
      end

      Printer.find_or_create_by!(name: "Front Counter Receipt") do |p|
        p.printer_type = "receipt"
        p.connection_type = "network"
        p.host = "192.168.1.100"
        p.port = 9100
        p.station = "Front counter"
        p.location = main_branch
        p.is_default = true
      end

      Printer.find_or_create_by!(name: "Kitchen Hot Line") do |p|
        p.printer_type = "kitchen"
        p.connection_type = "network"
        p.host = "192.168.1.101"
        p.port = 9100
        p.station = "Hot line"
        p.location = main_branch
        p.is_default = true
      end

      main_branch
    end
  end
end
