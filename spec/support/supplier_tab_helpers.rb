# frozen_string_literal: true

# The supplier page loads its active tab lazily into a Turbo frame. A plain GET
# returns only the shell; asking as the frame returns the tab itself.
module SupplierTabHelpers
  def get_supplier_tab(supplier, tab, **params)
    get admin_inventory_supplier_path(supplier, params.merge(tab: tab)),
      headers: { "Turbo-Frame" => Admin::Inventory::SuppliersController::TAB_FRAME }
  end
end

RSpec.configure do |config|
  config.include SupplierTabHelpers, type: :request
end
