# frozen_string_literal: true

require "csv"

module Admin
  module Inventory
    # Every alternate-unit conversion in the company on one reviewable page, with
    # the factor editable in place. The alternative is opening 250+ ingredient
    # forms to answer "is 1 carton really 12 bottles?".
    class UnitConversionsController < BaseController
      before_action :load_filters
      helper_method :filter_params

      SORT_COLUMNS = %w[ingredient base alt factor status].freeze
      FLAGS = %w[all check unverified ok].freeze
      STATUSES = %w[active inactive all].freeze

      def index
        authorize_inventory_index!(Unit)
        load_review

        respond_to do |format|
          format.html do
            @updated = params[:updated]
            load_form_options
            load_missing
          end
          format.csv do
            send_data review_csv,
              filename: "unit-conversions-#{Date.current}.csv",
              type: "text/csv; charset=utf-8"
          end
        end
      end

      # Saves the factors (and purchase-unit choice) the reviewer corrected,
      # touching only the rows whose value actually moved so the audit trail
      # stays a record of real decisions.
      def bulk_update
        authorize_inventory!(:manage_settings)
        @failures = []
        @updated = save_submitted_rows

        # Re-review after saving: a corrected rate moves its row out of "needs a
        # look" and changes the counts, and the reviewer should see that happen.
        load_review
        load_form_options
        load_missing

        respond_to do |format|
          format.turbo_stream { render status: (@failures.any? ? :unprocessable_entity : :ok) }
          format.html { redirect_to admin_inventory_unit_conversions_path(filter_params.merge(updated: @updated)) }
        end
      end

      private

      def load_filters
        @flag = FLAGS.include?(params[:flag].to_s) ? params[:flag].to_s : "all"
        @status = STATUSES.include?(params[:status].to_s) ? params[:status].to_s : "active"
        @view = params[:view].to_s == "missing" ? "missing" : "conversions"
        @query = params[:q].to_s.strip
        @unit_id = params[:unit_id].presence
        @base_unit_id = params[:base_unit_id].presence
        @category_id = params[:category_id].presence
        @sort = SORT_COLUMNS.include?(params[:sort].to_s) ? params[:sort].to_s : "ingredient"
        @direction = params[:dir].to_s == "desc" ? "desc" : "asc"
      end

      def load_review
        # The "other ingredients convert this pair differently" check has to see
        # the whole company, not just the filtered page, or narrowing the list
        # would quietly silence it.
        peers = IngredientUnit.includes(ingredient: :unit_ref).to_a
        @review = ::Inventory::UnitConversionReview.new(filtered_conversions, peers: peers)
        @rows = sort_rows(apply_flag(@review.rows))
        @counts = @review.rows.group_by(&:status).transform_values(&:size)
        @total = @review.rows.size
      end

      def filtered_conversions
        scope = IngredientUnit
          .includes(:unit_ref, ingredient: %i[unit_ref ingredient_category])
          .joins(:ingredient)

        scope = scope.where(ingredients: { active: true }) if @status == "active"
        scope = scope.where(ingredients: { active: false }) if @status == "inactive"
        scope = scope.where(unit_id: @unit_id) if @unit_id
        scope = scope.where(ingredients: { unit_id: @base_unit_id }) if @base_unit_id
        scope = scope.where(ingredients: { ingredient_category_id: @category_id }) if @category_id
        if @query.present?
          term = "%#{@query.downcase}%"
          scope = scope.where(
            "LOWER(ingredients.name) LIKE :term OR LOWER(ingredients.code) LIKE :term", term: term
          )
        end
        scope.order("ingredients.name")
      end

      def apply_flag(rows)
        case @flag
        when "check" then rows.select(&:check?)
        when "unverified" then rows.select(&:unverified?)
        when "ok" then rows.select(&:verified?)
        else rows
        end
      end

      # Status is worked out in Ruby, so ordering happens here rather than in
      # SQL — one page of conversions, never a paginated table.
      def sort_rows(rows)
        key = case @sort
        when "base" then ->(row) { [row.base_unit.to_s.downcase, row.ingredient.name.to_s.downcase] }
        when "alt" then ->(row) { [row.alt_unit.to_s.downcase, row.ingredient.name.to_s.downcase] }
        when "factor" then ->(row) { row.factor }
        when "status" then ->(row) { [status_rank(row), row.ingredient.name.to_s.downcase] }
        else ->(row) { row.ingredient.name.to_s.downcase }
        end
        sorted = rows.sort_by(&key)
        @direction == "desc" ? sorted.reverse : sorted
      end

      def status_rank(row)
        { check: 0, unverified: 1, ok: 2 }.fetch(row.status, 3)
      end

      # Ingredients measured in one unit only — nothing to get wrong yet, but
      # the gap is part of the review: a purchase unit no one set is why a
      # vendor invoice gets entered in the wrong measure.
      def load_missing
        scope = Ingredient.where.missing(:ingredient_units)
          .includes(:unit_ref, :ingredient_category)
        scope = scope.active if @status == "active"
        scope = scope.where(active: false) if @status == "inactive"
        scope = scope.where(ingredient_category_id: @category_id) if @category_id
        scope = scope.where(unit_id: @base_unit_id) if @base_unit_id
        if @query.present?
          term = "%#{@query.downcase}%"
          scope = scope.where("LOWER(name) LIKE :term OR LOWER(code) LIKE :term", term: term)
        end
        @missing_count = scope.count
        @missing = scope.order(:name) if @view == "missing"
      end

      def load_form_options
        @units = Unit.ordered
        @categories = IngredientCategory.order(:position, :name)
      end

      def save_submitted_rows
        submitted = params[:conversions]
        return 0 if submitted.blank?

        records = IngredientUnit.includes(:unit_ref, :ingredient).where(id: submitted.keys).index_by(&:id)
        # Attributes are read one at a time rather than mass-assigned, so the
        # per-row parameters need no permit list of their own.
        submitted.each_pair.sum do |id, attrs|
          record = records[id]
          next 0 if record.nil?

          apply_row(record, attrs) ? 1 : 0
        end
      end

      def apply_row(record, attrs)
        factor = attrs[:base_units_per_unit].to_s.strip
        purchase = ActiveModel::Type::Boolean.new.cast(attrs[:purchase_unit]).present?

        record.base_units_per_unit = factor if factor.present?
        record.purchase_unit = purchase
        return false unless record.changed?

        return true if record.save

        @failures << record
        false
      end

      # The filter state as the URL would carry it. The views build their links
      # and hidden fields from this rather than from the request's own query
      # string, which is empty on the save request that re-renders them.
      def filter_params
        {
          q: @query.presence, flag: (@flag unless @flag == "all"),
          status: (@status unless @status == "active"), view: (@view unless @view == "conversions"),
          unit_id: @unit_id, base_unit_id: @base_unit_id, category_id: @category_id,
          sort: (@sort unless @sort == "ingredient"), dir: (@direction unless @direction == "asc")
        }.compact
      end

      def review_csv
        CSV.generate(headers: true) do |csv|
          csv << [
            t("inventory.unit_conversions.csv.code"), t("inventory.unit_conversions.csv.ingredient"),
            t("inventory.unit_conversions.csv.category"), t("inventory.unit_conversions.csv.base_unit"),
            t("inventory.unit_conversions.csv.alt_unit"), t("inventory.unit_conversions.csv.factor"),
            t("inventory.unit_conversions.csv.expected"), t("inventory.unit_conversions.csv.status"),
            t("inventory.unit_conversions.csv.reason"), t("inventory.unit_conversions.csv.cost_per_unit"),
            t("inventory.unit_conversions.csv.on_hand")
          ]
          @rows.each do |row|
            csv << [
              row.ingredient.code, row.ingredient.name,
              row.ingredient.ingredient_category&.name,
              ::Ingredient.unit_display_label(row.base_unit),
              ::Ingredient.unit_display_label(row.alt_unit),
              row.factor.to_s("F"), row.expected&.round(6)&.to_s("F"),
              t("inventory.unit_conversions.status.#{row.status}"),
              helpers.unit_conversion_reason_text(row),
              (row.ingredient.cost_per_unit_cents.to_i * row.factor / 100).round(2).to_s("F"),
              (row.ingredient.quantity_on_hand.to_d / row.factor).round(3).to_s("F")
            ]
          end
        end
      end

      def record_for_policy
        Ingredient.new
      end
    end
  end
end
