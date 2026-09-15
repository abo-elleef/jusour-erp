# frozen_string_literal: true

module Inventory
  class ReverseManufacturingRunService
    class Error < StandardError; end

    def initialize(run:, user:)
      @run = run
      @user = user
      @template = run.manufacturing_template
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        restore_inputs!
        remove_unused_output!
        @run.update!(reversed_at: Time.current, reversed_by: @user)
      end

      # The output batch has been zeroed out, so the average of what remains has
      # moved with it.
      Inventory::SyncManufacturedCostJob.perform_later(@template.output_ingredient_id)

      @run
    end

    private

    def validate!
      raise Error, I18n.t("inventory.manufacturing.runs.errors.already_reversed") if @run.reversed?
      raise Error, I18n.t("inventory.manufacturing.runs.errors.location_missing") if @run.location.blank?
      raise Error, I18n.t("inventory.manufacturing.runs.errors.output_missing") if output_batch.blank?
      raise Error, I18n.t("inventory.manufacturing.runs.errors.output_used") unless @run.reversible?
    end

    def restore_inputs!
      restorations.each do |ingredient, quantity|
        next unless quantity.positive?

        StockAdjustment.create!(
          ingredient: ingredient,
          user: @user,
          location: @run.location,
          quantity_delta: quantity,
          adjustment_type: "production_consumption",
          maintain_batches: true,
          reason_notes: reversal_note("consumption", ingredient)
        )
      end
    end

    def remove_unused_output!
      batch = output_batch
      quantity = batch.quantity_remaining.to_d
      batch.update!(quantity_remaining: 0)

      StockAdjustment.create!(
        ingredient: batch.ingredient,
        user: @user,
        location: @run.location,
        stock_batch: batch,
        quantity_delta: -quantity,
        adjustment_type: "production_output",
        reason_notes: reversal_note("output")
      )
    end

    def restorations
      from_adjustments = consumption_adjustments.each_with_object(Hash.new(0.to_d)) do |adj, hash|
        hash[adj.ingredient] += adj.quantity_delta.to_d.abs
      end
      return from_adjustments if from_adjustments.any?

      @template.manufacturing_template_lines.includes(:ingredient).each_with_object(Hash.new(0.to_d)) do |line, hash|
        hash[line.ingredient] += line.base_quantity_used * @run.runs_count.to_d
      end
    end

    def consumption_adjustments
      StockAdjustment.where(adjustment_type: "production_consumption", location_id: @run.location_id)
        .where("reason_notes LIKE ?", "%#{@run.id}%")
        .where("quantity_delta < 0")
    end

    def output_batch
      @output_batch ||= @run.output_batch
    end

    def reversal_note(kind, ingredient = nil)
      I18n.t(
        "inventory.manufacturing.adjustment_#{kind}_reversal",
        template: @template.name,
        ingredient: ingredient&.name,
        output: @template.output_ingredient.name,
        number: @run.run_number
      )
    end
  end
end
