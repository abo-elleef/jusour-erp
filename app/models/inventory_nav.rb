# frozen_string_literal: true

# Single source of truth for the Inventory section's sidebar + tools nav.
# All tabs currently share inventory:view (section gate); keep permission on
# each tab so finer-grained keys can land later without reshaping the nav.
module InventoryNav
  GROUPS = [
    {
      key: :operations, icon: :operations, label: "inventory.tools.groups.operations",
      tabs: [
        { controller: "vendor_invoices", label: "inventory.tools.vendor_invoices",
          path: :admin_inventory_vendor_invoices_path, permission: "inventory:view" },
        { controller: "vendor_credit_notes", label: "inventory.tools.vendor_credit_notes",
          path: :admin_inventory_vendor_credit_notes_path, permission: "inventory:view" },
        { controller: "import_shipments", label: "inventory.tools.import_shipments",
          path: :admin_inventory_import_shipments_path, permission: "inventory:view",
          feature: :landed_cost },
        { controller: "stock_transfers",
          controllers: %w[stock_transfers stock_transfer_templates],
          label: "inventory.tools.stock_transfers",
          path: :admin_inventory_stock_transfers_path, permission: "inventory:view" },
        { controller: "stock_takes", label: "inventory.tools.stock_takes",
          path: :admin_inventory_stock_takes_path, permission: "inventory:view" },
        { controller: "manufacturing_templates",
          controllers: %w[manufacturing_templates manufacturing_runs manufacturing_template_lines],
          label: "inventory.tools.manufacturing",
          path: :admin_inventory_manufacturing_templates_path, permission: "inventory:view",
          feature: :manufacturing }
      ]
    },
    {
      key: :reports, icon: :reports, label: "inventory.tools.groups.reports",
      tabs: [
        { controller: "reports", action: "valuation", label: "inventory.tools.valuation",
          path: :admin_inventory_reports_valuation_path, permission: "inventory:view" },
        { controller: "reports", action: "variance", label: "inventory.tools.variance",
          path: :admin_inventory_reports_variance_path, permission: "inventory:view" },
        { controller: "reports", action: "transfer_trends", label: "inventory.tools.transfer_trends",
          path: :admin_inventory_reports_transfer_trends_path, permission: "inventory:view" }
      ]
    },
    {
      key: :setup, icon: :gear, label: "inventory.tools.groups.setup",
      tabs: [
        { controller: "suppliers", label: "inventory.tools.suppliers",
          path: :admin_inventory_suppliers_path, permission: "inventory:view" },
        { controller: "ingredients", label: "inventory.tools.ingredients",
          path: :admin_inventory_ingredients_path, permission: "inventory:view" },
        { controller: "ingredient_categories", label: "inventory.tools.ingredient_categories",
          path: :admin_inventory_ingredient_categories_path, permission: "inventory:view" },
        { controller: "units", label: "inventory.tools.units",
          path: :admin_inventory_units_path, permission: "inventory:view" }
      ]
    }
  ].freeze
end
