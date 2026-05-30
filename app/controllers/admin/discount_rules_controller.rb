# frozen_string_literal: true

module Admin
  class DiscountRulesController < BaseController
    before_action :set_rule, only: %i[edit update destroy]

    def index
      @discount_rules = policy_scope(DiscountRule).order(:name)
      authorize DiscountRule
    end

    def new
      @discount_rule = DiscountRule.new
      authorize @discount_rule
    end

    def create
      @discount_rule = DiscountRule.new(rule_params)
      authorize @discount_rule
      if @discount_rule.save
        redirect_to admin_discount_rules_path, notice: "Discount rule created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @discount_rule
    end

    def update
      authorize @discount_rule
      if @discount_rule.update(rule_params)
        redirect_to admin_discount_rules_path, notice: "Discount rule updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @discount_rule
      @discount_rule.destroy
      redirect_to admin_discount_rules_path, notice: "Discount rule removed."
    end

    private

    def set_rule
      @discount_rule = DiscountRule.find(params[:id])
    end

    def rule_params
      params.require(:discount_rule).permit(
        :name, :code, :discount_type, :discount_value, :minimum_order_cents,
        :applies_to, :applies_to_id, :active, :expires_at, :uses_remaining
      )
    end
  end
end
