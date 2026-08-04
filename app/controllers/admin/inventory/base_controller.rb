# frozen_string_literal: true

module Admin
  module Inventory
    class BaseController < Admin::BaseController
      include SessionDateRange

      before_action :authorize_inventory_access!

      private

      def authorize_inventory_access!
        return if current_user.can?("inventory:view")

        flash[:alert] = t("flash.inventory_access")
        redirect_to root_path
      end

      def inventory_policy
        InventoryPolicy.new(current_user, record_for_policy)
      end

      def record_for_policy
        @ingredient || @supplier || @vendor_invoice || @stock_take ||
          @manufacturing_template || @manufacturing_run || @stock_transfer || Ingredient.new
      end

      def authorize_inventory!(action)
        query = action.to_s.end_with?("?") ? action : :"#{action}?"
        authorize record_for_policy, query, policy_class: InventoryPolicy
      end

      def authorize_inventory_index!(record_class = Ingredient)
        authorize record_class, :index?, policy_class: InventoryPolicy
      end
    end
  end
end
