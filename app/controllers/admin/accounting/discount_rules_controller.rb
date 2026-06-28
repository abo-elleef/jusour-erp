# frozen_string_literal: true

module Admin
  module Accounting
    class DiscountRulesController < BaseController
      before_action :set_rule, only: %i[edit update destroy]

      def index
        @discount_rules = policy_scope(DiscountRule).order(:name)
        authorize DiscountRule
      end

      def new
        @discount_rule = DiscountRule.new(active: true, applies_to: "order", minimum_order_cents: 0)
        load_form_collections
        authorize @discount_rule
      end

      def create
        @discount_rule = DiscountRule.new(rule_params)
        authorize @discount_rule
        if @discount_rule.save
          redirect_to admin_accounting_discount_rules_path, notice: t("flash.discount_rule.created")
        else
          load_form_collections
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        load_form_collections
        authorize @discount_rule
      end

      def update
        authorize @discount_rule
        if @discount_rule.update(rule_params)
          redirect_to admin_accounting_discount_rules_path, notice: t("flash.discount_rule.updated")
        else
          load_form_collections
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @discount_rule
        @discount_rule.destroy
        redirect_to admin_accounting_discount_rules_path, notice: t("flash.discount_rule.removed")
      end

      private

      def set_rule
        @discount_rule = DiscountRule.find(params[:id])
      end

      def rule_params
        permitted = params.require(:discount_rule).permit(
          :name, :code, :discount_type, :discount_value, :minimum_order_pounds,
          :applies_to, :applies_to_id, :active, :expires_at, :uses_remaining
        )
        permitted[:applies_to_id] = nil if permitted[:applies_to] == "order"
        permitted
      end

      def load_form_collections
        @categories = Category.active.ordered
        @menu_items = MenuItem.ordered
      end
    end
  end
end
