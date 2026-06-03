# frozen_string_literal: true

module Admin
  class ModifierGroupsController < BaseController
    before_action :set_modifier_group, only: %i[show edit update destroy]

    def index
      @q = ModifierGroup.ransack(params[:q])
      @modifier_groups = policy_scope(@q.result).includes(:modifiers, :menu_items).ordered
      authorize ModifierGroup
    end

    def show
      authorize @modifier_group
      @modifiers = @modifier_group.modifiers
    end

    def new
      @modifier_group = ModifierGroup.new(required: false, multi_select: false)
      authorize @modifier_group
    end

    def create
      @modifier_group = ModifierGroup.new(modifier_group_params)
      authorize @modifier_group
      if @modifier_group.save
        redirect_to admin_modifier_group_path(@modifier_group), notice: t("flash.modifier_group.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @modifier_group
    end

    def update
      authorize @modifier_group
      if @modifier_group.update(modifier_group_params)
        redirect_to admin_modifier_group_path(@modifier_group), notice: t("flash.modifier_group.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @modifier_group
      if @modifier_group.menu_items.exists?
        redirect_to admin_modifier_groups_path,
                    alert: t("flash.modifier_group.cannot_delete_assigned")
        return
      end
      if @modifier_group.modifiers.joins(:order_item_modifiers).exists?
        redirect_to admin_modifier_groups_path,
                    alert: t("flash.modifier_group.cannot_delete_used")
        return
      end
      @modifier_group.destroy!
      redirect_to admin_modifier_groups_path, notice: t("flash.modifier_group.removed")
    end

    private

    def set_modifier_group
      @modifier_group = ModifierGroup.find(params[:id])
    end

    def modifier_group_params
      params.require(:modifier_group).permit(:name, :required, :multi_select, :position)
    end
  end
end
