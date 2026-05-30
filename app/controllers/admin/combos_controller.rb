# frozen_string_literal: true

module Admin
  class CombosController < BaseController
    before_action :set_combo, only: %i[edit update destroy]

    def index
      @combos = policy_scope(Combo).includes(:menu_items)
      authorize Combo
    end

    def new
      @combo = Combo.new
      3.times { @combo.combo_items.build }
      @menu_items = MenuItem.available
      authorize @combo
    end

    def create
      @combo = Combo.new(combo_params)
      authorize @combo
      if @combo.save
        redirect_to admin_combos_path, notice: "Combo created."
      else
        @menu_items = MenuItem.available
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @menu_items = MenuItem.available
      authorize @combo
    end

    def update
      authorize @combo
      if @combo.update(combo_params)
        redirect_to admin_combos_path, notice: "Combo updated."
      else
        @menu_items = MenuItem.available
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @combo
      @combo.destroy
      redirect_to admin_combos_path, notice: "Combo removed."
    end

    private

    def set_combo
      @combo = Combo.find(params[:id])
    end

    def combo_params
      params.require(:combo).permit(
        :name, :description, :price_cents, :active,
        combo_items_attributes: %i[id menu_item_id quantity _destroy]
      )
    end
  end
end
