# frozen_string_literal: true

module Admin
  module Inventory
    class SupplierIngredientsController < BaseController
      before_action :set_ingredient
      before_action :set_supplier_link, only: %i[update destroy]

      def create
        authorize_inventory!(:manage_settings)
        @supplier_link = @ingredient.supplier_ingredients.build(supplier_ingredient_params)
        if @supplier_link.save
          redirect_to edit_admin_inventory_ingredient_path(@ingredient), notice: t("flash.supplier_ingredient.assigned")
        else
          redirect_to edit_admin_inventory_ingredient_path(@ingredient),
                      alert: @supplier_link.errors.full_messages.to_sentence
        end
      end

      def update
        authorize_inventory!(:manage_settings)
        if @supplier_link.update(supplier_ingredient_params)
          redirect_to edit_admin_inventory_ingredient_path(@ingredient), notice: t("flash.supplier_ingredient.updated")
        else
          redirect_to edit_admin_inventory_ingredient_path(@ingredient),
                      alert: @supplier_link.errors.full_messages.to_sentence
        end
      end

      def destroy
        authorize_inventory!(:manage_settings)
        @supplier_link.destroy
        redirect_to edit_admin_inventory_ingredient_path(@ingredient), notice: t("flash.supplier_ingredient.removed")
      end

      private

      def set_ingredient
        @ingredient = Ingredient.find(params[:ingredient_id])
      end

      def set_supplier_link
        @supplier_link = @ingredient.supplier_ingredients.find(params[:id])
      end

      def supplier_ingredient_params
        permitted = params.require(:supplier_ingredient).permit(
          :supplier_id, :price_dollars, :preferred, :vendor_product_name, :vendor_sku
        )
        dollars = permitted.delete(:price_dollars)
        permitted[:price_cents] = (BigDecimal(dollars.to_s.presence || "0") * 100).round
        permitted
      end
    end
  end
end
