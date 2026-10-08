# frozen_string_literal: true

module Inventory
  # Builds (and saves as a draft) a StockTransfer pre-filled with one line per
  # output ingredient from a just-recorded batch of manufacturing runs — the
  # "transfer this batch" shortcut off the production sheet, so a worker isn't
  # retyping every item into a transfer by hand. Stays a draft: nothing moves
  # until someone reviews the quantities and sends it, same as any other
  # transfer.
  class BuildTransferFromManufacturingRunsService
    class Error < StandardError; end

    def initialize(run_ids:, to_location:, user:)
      @run_ids = Array(run_ids).map(&:to_s).reject(&:blank?)
      @to_location = to_location
      @user = user
    end

    def call
      raise Error, I18n.t("production.batch_transfer.errors.no_runs") if runs.empty?
      raise Error, I18n.t("production.batch_transfer.errors.location_required") if @to_location.blank?
      raise Error, I18n.t("production.batch_transfer.errors.mixed_locations") if from_location.blank?

      transfer = StockTransfer.new(
        status: "draft",
        from_location: from_location,
        to_location: @to_location,
        requested_by: @user,
        transferred_on: Date.current
      )

      output_totals.each_with_index do |(ingredient, quantity), index|
        transfer.stock_transfer_lines.build(
          ingredient: ingredient,
          unit: ingredient.unit,
          quantity_requested: quantity,
          position: index
        )
      end

      transfer.save!
      transfer
    end

    private

    def runs
      @runs ||= ManufacturingRun.where(id: @run_ids, reversed_at: nil)
        .includes(:location, manufacturing_template: :output_ingredient)
    end

    # All runs in one batch share the production location they were recorded
    # at; a mismatch here means the ids no longer describe one coherent batch.
    def from_location
      @from_location ||= begin
        locations = runs.filter_map(&:location).uniq
        locations.size == 1 ? locations.first : nil
      end
    end

    # Same math as RunManufacturingService's own output_quantity, summed per
    # output ingredient across every run in the batch.
    def output_totals
      runs.group_by { |run| run.manufacturing_template.output_ingredient }
        .transform_values { |group| group.sum { |run| run.runs_count.to_d * run.manufacturing_template.base_yield_quantity } }
    end
  end
end
