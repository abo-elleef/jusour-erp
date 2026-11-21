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

    before_action :set_menu_item, only: %i[show edit update destroy recipe_matrix]

    # Show page: a shell plus one Turbo frame that lazy-loads the active tab
    # from the same URL (?tab=), like the customer and supplier pages.
    TAB_FRAME = "menu_item_tab"
    TABS = %w[overview recipe sales history].freeze
    TAB_PAGE_SIZE = 25
    SALES_SORTS = {
      "date" => "orders.business_date %{dir}, orders.created_at %{dir}",
      "quantity" => "order_items.quantity %{dir}",
      # The expression, not its alias: pagy's count query keeps the ORDER BY
      # but drops the select that defines the alias.
      "amount" => "(#{::Accounting::RevenueCalculator::ORDER_ITEM_LINE_REVENUE}) %{dir}"
    }.freeze

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

    def show
      authorize @menu_item
      @tabs = TABS
      @tab = TABS.include?(params[:tab]) ? params[:tab] : TABS.first
      return unless turbo_frame_request_id == TAB_FRAME

      send(:"load_#{@tab}_tab")
      # The admin layout is set explicitly and would override turbo-rails'
      # bare frame layout.
      render "tab", layout: "turbo_rails/frame"
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

    # Which of the item's option groups change the recipe together. Changing
    # the choice starts the matrix over (MenuItemModifierGroup clears the rows).
    def recipe_matrix
      authorize @menu_item, :update?
      ticked = Array(params[:group_ids]).reject(&:blank?)
      errors = []
      MenuItemModifierGroup.transaction do
        @menu_item.menu_item_modifier_groups.includes(:modifier_group).each do |attachment|
          next if attachment.update(recipe_matrix: ticked.include?(attachment.modifier_group_id))

          errors << "#{attachment.modifier_group.name}: #{attachment.errors.full_messages.to_sentence}"
        end
        raise ActiveRecord::Rollback if errors.any?
      end
      redirect_to edit_admin_menu_item_path(@menu_item, anchor: "recipe-matrix"),
                  **(errors.any? ? { alert: errors.to_sentence } : { notice: t("menu.recipe_matrix.groups_saved") })
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

    # Details, where it sells and at what price, and its option groups.
    def load_overview_tab
      @branch_rows = @menu_item.location_menu_items.includes(:location).sort_by { |row| row.location.name.to_s }
      @attachments = @menu_item.menu_item_modifier_groups.includes(modifier_group: :modifiers)
    end

    # What one of it uses: the item recipe, and per combination when the item
    # has a recipe matrix. Read-only; changes are made on the edit page.
    def load_recipe_tab
      @recipes = @menu_item.recipes.joins(:ingredient).includes(:unit_ref, ingredient: :unit_ref).order("ingredients.name")
      @recipe_matrix = ::Inventory::RecipeMatrix.new(@menu_item)
    end

    # Completed sales of the item between two business days (this month by
    # default), totals first, then each line, newest first.
    def load_sales_tab
      @sales_to = parse_date(params[:to]) || Date.current
      @sales_from = parse_date(params[:from]) || @sales_to.beginning_of_month
      @sales_from, @sales_to = @sales_to, @sales_from if @sales_from > @sales_to

      lines = OrderItem.joins(:order)
        .where(menu_item_id: @menu_item.id, orders: { status: "completed", business_date: @sales_from..@sales_to })
      @sales_units = lines.sum(:quantity)
      @sales_revenue_cents = ::Accounting::RevenueCalculator.order_item_revenue(lines)
      @sales_cost_cents = ::Inventory::ConsumptionByCombo.new(lines).cost_cents_by_menu_item.fetch(@menu_item.id, 0)

      @sales_sort = SALES_SORTS.key?(params[:sort]) ? params[:sort] : "date"
      @sales_dir = params[:dir] == "asc" ? "asc" : "desc"
      scope = lines
        .select("order_items.*", "(#{::Accounting::RevenueCalculator::ORDER_ITEM_LINE_REVENUE}) AS line_revenue_cents")
        .includes(:order, :order_item_modifiers)
        .order(Arel.sql(format(SALES_SORTS[@sales_sort], dir: @sales_dir.upcase)))
      @sales_pagy, @sales_lines = pagy(:offset, scope, limit: TAB_PAGE_SIZE)
    end

    def load_history_tab
      @audits = @menu_item.audits.includes(:user).reorder(version: :desc)
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def load_modifier_groups_for_form
      @all_modifier_groups = ModifierGroup.includes(:modifiers).ordered
      @assigned_modifier_group_ids = @menu_item.modifier_group_ids
    end

    def load_recipes_for_form
      @recipe_matrix = ::Inventory::RecipeMatrix.new(@menu_item)
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
