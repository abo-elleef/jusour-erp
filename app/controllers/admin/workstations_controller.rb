# frozen_string_literal: true

module Admin
  class WorkstationsController < BaseController
    before_action :set_workstation, only: %i[edit update destroy]

    def index
      authorize Workstation
      @workstations = policy_scope(Workstation).includes(:location, :receipt_printer).ordered
      @workstations = @workstations.where(location_id: params[:location_id]) if params[:location_id].present?
    end

    def new
      @workstation = Workstation.new(active: true, location_id: params[:location_id])
      authorize @workstation
      load_form_data
    end

    def create
      @workstation = Workstation.new(workstation_params)
      authorize @workstation
      if @workstation.save
        redirect_to admin_workstations_path, notice: t("flash.workstation.created")
      else
        load_form_data
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @workstation
      load_form_data
    end

    def update
      authorize @workstation
      if @workstation.update(workstation_params)
        redirect_to admin_workstations_path, notice: t("flash.workstation.updated")
      else
        load_form_data
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @workstation
      @workstation.destroy
      redirect_to admin_workstations_path, notice: t("flash.workstation.removed")
    end

    private

    def set_workstation
      @workstation = Workstation.find(params[:id])
    end

    def workstation_params
      params.require(:workstation).permit(:name, :location_id, :receipt_printer_id, :active)
    end

    def load_form_data
      @locations = Location.active.branches.ordered
      location = @workstation.location || @locations.find { |l| l.id == @workstation.location_id } || @locations.first
      @receipt_printers = if location
                            Printer.active.for_location(location).where(printer_type: "receipt").order(:name)
                          else
                            Printer.none
                          end
    end
  end
end
