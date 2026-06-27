# frozen_string_literal: true

module SuperAdmin
  class LocationsController < BaseController
    before_action :set_company
    before_action :set_location, only: %i[edit update]

    def new
      @location = Location.new(location_type: "branch")
    end

    def create
      @location = Location.unscoped.new(location_params)
      @location.company = @company
      if @location.save
        redirect_to super_admin_company_path(@company), notice: "Branch created."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit; end

    def update
      if @location.update(location_params)
        redirect_to super_admin_company_path(@company), notice: "Branch updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_company
      @company = Company.unscoped.find(params[:company_id])
    end

    def set_location
      @location = Location.unscoped.where(company_id: @company.id).find(params[:id])
    end

    def location_params
      params.require(:location).permit(:name, :slug, :location_type, :active, :address, :phone, :whatsapp_number, :public_menu_enabled)
    end
  end
end
