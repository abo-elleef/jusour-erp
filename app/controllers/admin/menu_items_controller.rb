# frozen_string_literal: true

module Admin
  class MenuItemsController < BaseController
    # Header sort key => SQL. Name, code and category ignore case.
    SORT_COLUMNS = {
      "code" => "LOWER(menu_items.code)",
      "name" => "LOWER(menu_items.name)",
      "category" => "LOWER(categories.name)",
      "price" => "menu_items.base_price_cents",
      "tax" => "menu_items.tax_category",
      "status" => "menu_items.available"
    }.freeze

    before_action :set_menu_item, only: %i[edit update destroy]

    def index
      scope = policy_scope(MenuItem).includes(:category, :modifier_groups, image_attachment: :blob)
      @total_count = scope.count
      @available_count = scope.where(available: true).count
      @unavailable_count = @total_count - @available_count
      @sort = SORT_COLUMNS.key?(params[:sort].to_s) ? params[:sort].to_s : nil
      @direction = params[:dir].to_s == "desc" ? "desc" : "asc"
      @menu_items = scope.joins(:category)
      @menu_items = @menu_items.order(Arel.sql("#{SORT_COLUMNS[@sort]} #{@direction.upcase}")) if @sort
      # Unsorted (and as the tiebreak): the menu's own order, as on the POS.
      @menu_items = @menu_items.order("categories.position ASC, menu_items.position ASC, menu_items.name ASC")
      if params[:category_id].present?
        @menu_items = @menu_items.where(category_id: params[:category_id])
        @filtered_category_id = params[:category_id]
      end
      if (@search = params[:search].to_s.strip).present?
        @menu_items = @menu_items.where("menu_items.name ILIKE :s OR menu_items.code ILIKE :s", s: "%#{@search}%")
      end
      @categories = Category.active.ordered
      authorize MenuItem
    end

    def new
      @menu_item = MenuItem.new(available: true, tax_category: "food")
      load_modifier_groups_for_form
      @categories = Category.active.ordered
      authorize @menu_item
    end

    def create
      @menu_item = MenuItem.new(menu_item_params)
      authorize @menu_item
      if @menu_item.save
        sync_modifier_groups!(@menu_item)
        redirect_to admin_menu_items_path, notice: t("flash.menu_item.created")
      else
        load_modifier_groups_for_form
        @categories = Category.active.ordered
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      load_modifier_groups_for_form
      load_recipes_for_form
      @categories = Category.active.ordered
      authorize @menu_item
      @audits = @menu_item.audits.includes(:user).reorder(version: :desc)
    end

    def update
      authorize @menu_item
      if @menu_item.update(menu_item_params)
        sync_modifier_groups!(@menu_item)
        redirect_to admin_menu_items_path, notice: t("flash.menu_item.updated")
      else
        load_modifier_groups_for_form
        load_recipes_for_form
        @categories = Category.active.ordered
        @audits = @menu_item.audits.includes(:user).reorder(version: :desc)
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @menu_item
      if @menu_item.order_items.exists? || @menu_item.combo_items.exists?
        redirect_to admin_menu_items_path,
                    alert: t("flash.menu_item.cannot_delete_used")
        return
      end
      @menu_item.destroy
      redirect_to admin_menu_items_path, notice: t("flash.menu_item.removed")
    end

    private

    def set_menu_item
      @menu_item = MenuItem.includes(:modifier_groups).find(params[:id])
    end

    def load_modifier_groups_for_form
      @all_modifier_groups = ModifierGroup.includes(:modifiers).ordered
      @assigned_modifier_group_ids = @menu_item.modifier_group_ids
    end

    def load_recipes_for_form
      @recipes = @menu_item.recipes.joins(:ingredient).includes(:ingredient).order("ingredients.name")
      assigned_ids = @recipes.map(&:ingredient_id)
      @recipe_ingredients = Ingredient.active.includes(:ingredient_units).where.not(id: assigned_ids).order(:name)
    end

    def sync_modifier_groups!(menu_item)
      ids = Array(params.dig(:menu_item, :modifier_group_ids)).reject(&:blank?)
      menu_item.menu_item_modifier_groups.where.not(modifier_group_id: ids).destroy_all
      ids.each_with_index do |group_id, index|
        join = menu_item.menu_item_modifier_groups.find_or_initialize_by(modifier_group_id: group_id)
        join.position = index
        join.save!
      end
    end

    def menu_item_params
      params.require(:menu_item).permit(
        :category_id, :name, :code, :description, :base_price_pounds, :tax_category,
        :available, :position, :image
      )
    end
  end
end
