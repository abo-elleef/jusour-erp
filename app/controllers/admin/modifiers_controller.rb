# frozen_string_literal: true

module Admin
  class ModifiersController < BaseController
    before_action :set_modifier_group
    before_action :set_modifier, only: %i[edit update destroy]

    def new
      @modifier = @modifier_group.modifiers.build
      authorize @modifier
    end

    def create
      @modifier = @modifier_group.modifiers.build(modifier_params)
      authorize @modifier
      if @modifier.save
        redirect_to admin_modifier_group_path(@modifier_group), notice: t("flash.modifier.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @modifier
      @modifier_recipes = @modifier.modifier_recipes.includes(:unit_ref, ingredient: :ingredient_units)
      used_ids = @modifier_recipes.map(&:ingredient_id)
      @recipe_ingredients = Ingredient.active.includes(:ingredient_units).where.not(id: used_ids).order(:name)
    end

    def update
      authorize @modifier
      if params[:toggle_active].present?
        # One-click Activate/Deactivate from the group page: only flips active.
        @modifier.update!(active: !@modifier.active?)
        key = @modifier.active? ? "activated" : "deactivated"
        redirect_to admin_modifier_group_path(@modifier_group), notice: t("flash.modifier.#{key}", name: @modifier.name)
      elsif @modifier.update(modifier_params)
        redirect_to admin_modifier_group_path(@modifier_group), notice: t("flash.modifier.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @modifier
      if @modifier.order_item_modifiers.exists?
        redirect_to admin_modifier_group_path(@modifier_group),
                    alert: t("flash.modifier.cannot_delete_used")
        return
      end
      @modifier.destroy!
      redirect_to admin_modifier_group_path(@modifier_group), notice: t("flash.modifier.removed")
    end

    private

    def set_modifier_group
      @modifier_group = ModifierGroup.find(params[:modifier_group_id])
    end

    def set_modifier
      @modifier = @modifier_group.modifiers.find(params[:id])
    end

    def modifier_params
      params.require(:modifier).permit(:name, :price_adjustment_pounds, :position, :active)
    end
  end
end
