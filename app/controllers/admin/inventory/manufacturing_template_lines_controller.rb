# frozen_string_literal: true

module Admin
  module Inventory
    class ManufacturingTemplateLinesController < BaseController
      before_action :set_template

      def create
        authorize_inventory!(:update)
        @line = @template.manufacturing_template_lines.build(line_params)
        if @line.save
          redirect_to admin_inventory_manufacturing_template_path(@template),
            notice: t("flash.manufacturing_template_line.added")
        else
          redirect_to admin_inventory_manufacturing_template_path(@template),
            alert: @line.errors.full_messages.to_sentence
        end
      end

      def destroy
        authorize_inventory!(:update)
        @template.manufacturing_template_lines.find(params[:id]).destroy!
        redirect_to admin_inventory_manufacturing_template_path(@template),
          notice: t("flash.manufacturing_template_line.removed")
      end

      private

      def set_template
        @template = ManufacturingTemplate.find(params[:manufacturing_template_id])
      end

      def line_params
        params.require(:manufacturing_template_line).permit(:ingredient_id, :quantity_used)
      end
    end
  end
end
