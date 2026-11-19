# frozen_string_literal: true

# A self-contained distribution company for walking through the Bazzar sales
# flow end to end: whole-number quantities, a card machine that settles at
# once, per-method payment approvers, the shipping track, and the owner's
# role × stage grid with its notifications.
#
# LOCAL ONLY — refuses to run in production. Creates a new company; touches no
# other tenant. Every demo user shares one password, written to
# tmp/bazzar_sales_demo_credentials.txt (gitignored), never printed.
#
#   bin/rails demo:bazzar_sales
#   DEMO_SLUG=bazzar-demo-2 bin/rails demo:bazzar_sales
namespace :demo do
  desc "Create a local Bazzar sales-flow demo company (not for production)"
  task bazzar_sales: :environment do
    abort "Refusing to run in production." if Rails.env.production?

    slug = ENV.fetch("DEMO_SLUG", "bazzar-sales-demo")
    abort "A company with slug #{slug} already exists — pass a new DEMO_SLUG." if Company.unscoped.exists?(slug: slug)

    password = ENV["DEMO_PASSWORD"].presence || "Demo-#{SecureRandom.alphanumeric(12)}"
    domain = "#{slug}.test"
    people = {}

    ActiveRecord::Base.transaction do
      company = Company.create!(name: "Bazzar Sales Demo", slug: slug, business_type: "distribution",
                                locale: "ar", timezone: "Africa/Cairo", currency: "EGP")
      Current.company = company

      # --- Roles: one per job in Bazzar's flow -------------------------------
      # Every role starts with sales:see_all, as the slice-E migration leaves
      # them; take it off "Sales rep" to see a rep limited to their own content.
      roles = {
        sales_rep:        ["Sales rep",         %w[dashboard:view customers:manage leads:view leads:manage leads:reports]],
        accounts:         ["Accounts",          %w[dashboard:view customers:manage sales:confirm_payments accounting:reports]],
        wallet_holder:    ["Wallet holder",     %w[customers:manage]],
        warehouse:        ["Warehouse",         %w[customers:manage sales:dispatch inventory:view]],
        delivery_checker: ["Delivery checker",  %w[customers:manage sales:complete_shipping]]
      }.to_h do |key, (name, perms)|
        perms += %w[sales:see_all]
        [key, Role.create!(company: company, key: "demo_#{key}", name: name, permissions: perms)]
      end

      add_user = lambda do |key, name, role: nil, builtin: nil|
        user = User.new(company: company, name: name, email: "#{key}@#{domain}",
                        password: password, password_confirmation: password)
        if builtin
          user.role = builtin
        else
          user.role = "custom"
          user.role_id = role.id
        end
        user.save!
        people[key] = user
      end
      add_user.call(:owner, "Demo Owner", builtin: "owner")
      add_user.call(:rep, "Mona (sales)", role: roles[:sales_rep])
      add_user.call(:rep2, "Ali (sales)", role: roles[:sales_rep])
      add_user.call(:accounts, "Hany (accounts)", role: roles[:accounts])
      add_user.call(:saif, "Saif (wallet)", role: roles[:wallet_holder])
      add_user.call(:naggar, "El-Naggar (wallet)", role: roles[:wallet_holder])
      add_user.call(:warehouse, "Karim (warehouse)", role: roles[:warehouse])
      add_user.call(:checker, "Nour (delivery checks)", role: roles[:delivery_checker])

      # --- Owner's role × stage grid -----------------------------------------
      grid = {
        sales_rep:        { see: %w[draft pending_payment_confirmation confirmed waiting_for_shipping shipped shipping_completed void],
                            notify: %w[shipping_completed] },
        accounts:         { see: %w[pending_payment_confirmation confirmed waiting_for_shipping shipped shipping_completed void historical],
                            notify: %w[void] },
        wallet_holder:    { see: %w[pending_payment_confirmation], notify: [] },
        warehouse:        { see: %w[waiting_for_shipping shipped], notify: %w[waiting_for_shipping] },
        delivery_checker: { see: %w[shipped shipping_completed], notify: %w[shipped] }
      }
      grid.each do |key, cfg|
        CustomerInvoice::STAGES.each do |stage|
          Sales::StageAccess.create!(role: roles[key], stage: stage, can_see: cfg[:see].include?(stage),
                                     notify: cfg[:notify].include?(stage))
        end
      end

      # --- Stock, customers, courier -----------------------------------------
      location = Location.create!(company: company, name: "Main warehouse")
      category = IngredientCategory.create!(company: company, name: "Dental supplies")
      products = {
        "Implant kit" => 250_000, "Composite syringe" => 45_000,
        "Impression tray (box)" => 12_000, "Surgical gloves (box)" => 9_500
      }.to_h do |name, price|
        product = Ingredient.create!(company: company, ingredient_category: category, name: name, unit: "pieces",
                                     selling_price_cents: price, cost_per_unit_cents: (price * 0.6).round)
        StockBatch.create!(ingredient: product, location: location, quantity_received: 200, quantity_remaining: 200,
                           cost_per_unit_cents: (price * 0.6).round, received_on: Date.current)
        [name, product]
      end
      # Mona owns the first two, Ali the third; the fourth waits for a manager.
      owners = [people[:rep], people[:rep], people[:rep2], nil]
      customers = ["Smile Clinic", "Dr. Ahmed Fathy", "Nile Dental Center", "Delta Smile (unassigned)"].map.with_index do |name, i|
        Customer.create!(company: company, name: name, customer_type: i.zero? ? "commercial" : "regular",
                         phone: "0100000000#{i}", assigned_user: owners[i])
      end
      [[people[:rep], "Cairo Ortho Lead"], [people[:rep2], "Giza Implants Lead"]].each_with_index do |(user, name), i|
        Lead.create!(company: company, name: name, phone: "0120000000#{i}", created_by: people[:owner], assigned_user: user)
      end
      courier = ShippingCompany.create!(company: company, name: "Bosta (demo)")

      # --- Bazzar's payment methods, each into its own account ---------------
      method = lambda do |name, approvers: [], instant: false|
        treasury = Treasury.create!(company: company, name: name, treasury_type: "bank",
                                    balance_cents: 0, opening_balance_cents: 0)
        pm = Sales::PaymentMethod.create!(company: company, name: name, treasury: treasury,
                                          requires_approval: !instant)
        pm.approvers << approvers
        pm
      end
      methods = {
        instapay: method.call("InstaPay", approvers: [people[:accounts]]),
        saif: method.call("Vodafone Cash — Saif", approvers: [people[:saif]]),
        naggar: method.call("Vodafone Cash — El-Naggar", approvers: [people[:naggar]]),
        cib: method.call("CIB", approvers: [people[:accounts]]),
        qnb: method.call("QNB", approvers: [people[:accounts]]),
        card: method.call("Card machine", instant: true)
      }

      # --- Invoices at every stage, recorded by the sales rep ----------------
      new_invoice = lambda do |customer:, payment:, delivery:, lines:, sales_method: nil|
        recorder = customer.assigned_user || people[:rep]
        inv = CustomerInvoice.new(company: company, customer: customer, user: recorder, salesperson: recorder,
                                  location: location,
                                  invoice_date: Date.current, payment_method: payment,
                                  fulfillment_method: delivery ? "delivery" : "pickup",
                                  shipping_company: delivery ? courier : nil, sales_payment_method: sales_method,
                                  standard_delivery_fee_cents: delivery ? 5_000 : 0,
                                  delivery_fee_cents: delivery ? 5_000 : 0)
        lines.each do |product_name, qty|
          inv.customer_invoice_lines.build(ingredient: products[product_name], quantity: qty, unit: "pieces")
        end
        inv.save!
        inv
      end
      as = lambda do |key|
        Current.user = people[key]
        people[key]
      end
      confirm = ->(inv) { Sales::ConfirmCustomerInvoiceService.new(inv, as.call(:rep)).call }

      new_invoice.call(customer: customers[0], payment: "on_account", delivery: false,
                       lines: { "Implant kit" => 2 })                                   # draft

      pending = new_invoice.call(customer: customers[1], payment: "online", delivery: true,
                                 sales_method: methods[:saif], lines: { "Composite syringe" => 3 })
      confirm.call(pending)                                                              # awaiting Saif

      waiting = new_invoice.call(customer: customers[2], payment: "cash_on_delivery", delivery: true,
                                 lines: { "Surgical gloves (box)" => 10, "Impression tray (box)" => 4 })
      confirm.call(waiting)                                                              # waiting for shipping

      shipped = new_invoice.call(customer: customers[0], payment: "cash_on_delivery", delivery: true,
                                 lines: { "Implant kit" => 1 })
      confirm.call(shipped)
      Sales::DispatchCustomerInvoiceService.new(shipped, as.call(:warehouse)).call       # with the courier

      delivered = new_invoice.call(customer: customers[1], payment: "online", delivery: true,
                                   sales_method: methods[:instapay], lines: { "Composite syringe" => 2 })
      confirm.call(delivered)
      Sales::ConfirmCustomerInvoiceService.new(delivered, as.call(:accounts)).call       # approved
      Sales::DispatchCustomerInvoiceService.new(delivered, as.call(:warehouse)).call
      Sales::CompleteShippingService.new(delivered, as.call(:checker)).call              # delivered

      card = new_invoice.call(customer: customers[2], payment: "online", delivery: false,
                              sales_method: methods[:card], lines: { "Surgical gloves (box)" => 5 })
      confirm.call(card)                                                                 # paid at once
    ensure
      Current.user = nil
    end

    path = Rails.root.join("tmp/bazzar_sales_demo_credentials.txt")
    File.write(path, <<~TXT)
      Bazzar sales demo — #{slug} (local only)
      Password for every user: #{password}

      #{people.map { |key, u| format('%-10s %s  (%s)', key, u.email, u.name) }.join("\n")}
    TXT
    File.chmod(0o600, path)

    puts "Demo company ready: Bazzar Sales Demo (slug=#{slug})"
    puts "Users: #{people.values.map(&:email).join(', ')}"
    puts "Shared password written to #{path}"
  end
end
