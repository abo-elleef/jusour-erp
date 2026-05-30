# frozen_string_literal: true

module Admin
  class MenuItemsController < BaseController
    before_action :set_menu_item, only: %i[edit update destroy]

    def index
      @menu_items = policy_scope(MenuItem)
        .includes(:category, :modifier_groups, image_attachment: :blob)
        .joins(:category)
        .order("categories.position ASC, menu_items.position ASC, menu_items.name ASC")
      @categories = Category.active.ordered
      authorize MenuItem
    end

    def new
      @menu_item = MenuItem.new(available: true, tax_category: "food")
      build_nested_modifiers
      @categories = Category.active.ordered
      authorize @menu_item
    end

    def create
      @menu_item = MenuItem.new(menu_item_params)
      authorize @menu_item
      if @menu_item.save
        redirect_to admin_menu_items_path, notice: "Menu item created."
      else
        build_nested_modifiers
        @categories = Category.active.ordered
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      build_nested_modifiers
      @categories = Category.active.ordered
      authorize @menu_item
    end

    def update
      authorize @menu_item
      if @menu_item.update(menu_item_params)
        redirect_to admin_menu_items_path, notice: "Menu item updated."
      else
        @categories = Category.active.ordered
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @menu_item
      if @menu_item.order_items.exists? || @menu_item.combo_items.exists?
        redirect_to admin_menu_items_path,
                    alert: "Cannot delete: this item is used in orders or combos."
        return
      end
      @menu_item.destroy
      redirect_to admin_menu_items_path, notice: "Menu item removed."
    end

    private

    def set_menu_item
      @menu_item = MenuItem.includes(modifier_groups: :modifiers).find(params[:id])
    end

    def build_nested_modifiers
      return if @menu_item.modifier_groups.any?

      group = @menu_item.modifier_groups.build(required: false, multi_select: false)
      group.modifiers.build
    end

    def menu_item_params
      params.require(:menu_item).permit(
        :category_id, :name, :description, :base_price_cents, :tax_category,
        :available, :position, :image,
        modifier_groups_attributes: [
          :id, :name, :required, :multi_select, :position, :_destroy,
          { modifiers_attributes: %i[id name price_adjustment_cents position _destroy] }
        ]
      )
    end
  end
end
