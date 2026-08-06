# frozen_string_literal: true

# Bootstrap an isolated fried-chicken demo company for client demos.
# Does NOT modify other tenants. Prefer this over `db:seed` on production.
#
#   DEMO_SLUG=demo-fried-chicken DEMO_PASSWORD='Secret123' bin/rails demo:fried_chicken
#   DEMO_SLUG=acme-chicken DEMO_NAME='Acme Chicken Demo' bin/rails demo:fried_chicken
namespace :demo do
  desc "Create an isolated fried-chicken demo company (unique DEMO_SLUG required)"
  task fried_chicken: :environment do
    slug = ENV.fetch("DEMO_SLUG", "demo-fried-chicken")
    name = ENV["DEMO_NAME"]
    password = ENV["DEMO_PASSWORD"]

    begin
      result = Demo::FriedChickenBootstrap.call(
        slug: slug,
        name: name,
        password: password
      )
    rescue ArgumentError => e
      abort "ERROR: #{e.message}"
    end

    company = result.company
    puts "Demo company ready: #{company.name} (slug=#{company.slug}, id=#{company.id})"
    puts "Login:  #{result.owner_email} / #{result.password}"
    puts "Also:   manager@#{company.slug}.demo, cashier@#{company.slug}.demo, kitchen@#{company.slug}.demo"
    puts "Menu items: #{MenuItem.unscoped.where(company_id: company.id, available: true).count}"
  end
end
