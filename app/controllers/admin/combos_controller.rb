# frozen_string_literal: true

module Admin
  class CombosController < BaseController
    before_action :set_combo, only: %i[edit update destroy]

    def index
      scope = policy_scope(Combo)
      @total_count = scope.count
      @active_count = scope.where(active: true).count
      @inactive_count = @total_count - @active_count
      @combos = scope.includes(combo_items: :menu_item).order(:name)
      authorize Combo
    end

    def new
      @combo = Combo.new
      build_combo_items
      load_form_data
      authorize @combo
    end

    def create
      @combo = Combo.new(combo_params)
      authorize @combo
      if @combo.save
        redirect_to admin_combos_path, notice: t("flash.combo.created")
      else
        build_combo_items
        load_form_data
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      build_combo_items
      load_form_data
      authorize @combo
    end

    def update
      authorize @combo
      if @combo.update(combo_params)
        redirect_to admin_combos_path, notice: t("flash.combo.updated")
      else
        build_combo_items
        load_form_data
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @combo
      @combo.destroy
      redirect_to admin_combos_path, notice: t("flash.combo.removed")
    end

    private

    def set_combo
      @combo = Combo.find(params[:id])
    end

    def build_combo_items
      remaining = 3 - @combo.combo_items.reject(&:marked_for_destruction?).size
      remaining.times { @combo.combo_items.build } if remaining.positive?
    end

    def load_form_data
      @menu_items = MenuItem.available.includes(:category).order(:name)
    end

    def combo_params
      params.require(:combo).permit(
        :name, :description, :price_cents, :active,
        combo_items_attributes: %i[id menu_item_id quantity _destroy]
      )
    end
  end
end
