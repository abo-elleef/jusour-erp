# frozen_string_literal: true

module Admin
  class MenuPromosController < BaseController
    before_action :set_menu_promo, only: %i[edit update destroy]

    def index
      scope = policy_scope(MenuPromo)
      @active_now_count = scope.active_at.count
      @upcoming_count = scope.active.where("starts_at > ?", Time.current).count
      @menu_promos = scope.includes(:menu_item, :location).ordered
      authorize MenuPromo
    end

    def new
      @menu_promo = MenuPromo.new(
        active: true,
        highlight: true,
        starts_at: Time.current.beginning_of_hour,
        ends_at: 3.days.from_now.end_of_day
      )
      load_form_data
      authorize @menu_promo
    end

    def create
      @menu_promo = MenuPromo.new(menu_promo_params)
      authorize @menu_promo
      if @menu_promo.save
        redirect_to admin_menu_promos_path, notice: t("flash.menu_promo.created")
      else
        load_form_data
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      load_form_data
      authorize @menu_promo
    end

    def update
      authorize @menu_promo
      if @menu_promo.update(menu_promo_params)
        redirect_to admin_menu_promos_path, notice: t("flash.menu_promo.updated")
      else
        load_form_data
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @menu_promo
      @menu_promo.destroy
      redirect_to admin_menu_promos_path, notice: t("flash.menu_promo.removed")
    end

    private

    def set_menu_promo
      @menu_promo = MenuPromo.find(params[:id])
    end

    def load_form_data
      @menu_items = MenuItem.ordered.includes(:category)
      @locations = Location.active.branches.ordered
    end

    def menu_promo_params
      params.require(:menu_promo).permit(
        :name, :menu_item_id, :location_id, :promo_price_pounds,
        :starts_at, :ends_at, :highlight, :active
      )
    end
  end
end
