# frozen_string_literal: true

module Admin
  module Inventory
    # Moves a source ingredient's balance into a target ("consolidate"): the source
    # is a vendor-named duplicate of the same physical item. Both stay active.
    class IngredientConsolidationsController < BaseController
      before_action :set_ingredient

      # Target picker + per-location preview.
      def new
        authorize_inventory!(:adjust)
        @source_locations = @ingredient.ingredient_locations.where.not(quantity_on_hand: 0).includes(:location).to_a
        @targets = Ingredient.active
          .where(company_id: @ingredient.company_id, unit_id: @ingredient.unit_id)
          .where.not(id: @ingredient.id)
          .order(:name)
        @target = @targets.find_by(id: params[:target_id]) if params[:target_id].present?
      end

      def create
        authorize_inventory!(:adjust)
        target = Ingredient.active.find_by(id: params[:target_id])
        if target.nil?
          redirect_to new_admin_inventory_ingredient_consolidation_path(@ingredient),
                      alert: t("inventory.consolidations.errors.target_missing")
          return
        end

        result = ::Inventory::ConsolidateIngredientBalance.call(
          source: @ingredient, target: target, user: current_user
        )
        redirect_to admin_inventory_ingredient_path(target),
                    notice: t("flash.consolidation.done",
                              source: @ingredient.name, target: target.name,
                              count: result.locations_moved)
      rescue ::Inventory::ConsolidateIngredientBalance::Error => e
        redirect_to new_admin_inventory_ingredient_consolidation_path(@ingredient, target_id: params[:target_id]),
                    alert: t("inventory.consolidations.errors.#{e.message}", default: t("inventory.consolidations.errors.generic"))
      end

      private

      def set_ingredient
        @ingredient = Ingredient.find(params[:ingredient_id])
      end

      def record_for_policy
        @ingredient
      end
    end
  end
end
