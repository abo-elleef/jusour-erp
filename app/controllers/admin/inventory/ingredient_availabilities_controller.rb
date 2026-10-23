# frozen_string_literal: true

module Admin
  module Inventory
    # One grid for the location scope that otherwise lives on each ingredient's
    # edit form: "all locations" (including ones added later) or an explicit set.
    # Stock on hand is a different screen — this only decides where an ingredient
    # may be used.
    class IngredientAvailabilitiesController < BaseController
      before_action :load_filters
      helper_method :filter_params

      STATUSES = %w[active inactive all].freeze
      AVAILABILITIES = %w[all everywhere limited].freeze
      SORT_COLUMNS = %w[name code].freeze

      def index
        authorize_inventory_index!(Ingredient)
        load_locations
        load_ingredients
      end

      def bulk_update
        authorize_inventory!(:manage_settings)
        load_locations
        updated = apply_changes

        redirect_to admin_inventory_ingredient_availabilities_path(filter_params),
          notice: t("inventory.ingredient_availabilities.saved", count: updated)
      end

      private

      def load_filters
        @status = STATUSES.include?(params[:status].to_s) ? params[:status].to_s : "active"
        @availability = AVAILABILITIES.include?(params[:availability].to_s) ? params[:availability].to_s : "all"
        @query = params[:q].to_s.strip
        @category_id = params[:category_id].presence
        @sort = SORT_COLUMNS.include?(params[:sort].to_s) ? params[:sort].to_s : "name"
        @direction = params[:dir].to_s == "desc" ? "desc" : "asc"
      end

      def filter_params
        {
          q: @query.presence,
          status: (@status unless @status == "active"),
          category_id: @category_id,
          availability: (@availability unless @availability == "all"),
          sort: (@sort unless @sort == "name"),
          dir: (@direction unless @direction == "asc")
        }.compact
      end

      def load_locations
        @locations = Location.active.ordered.to_a
      end

      def load_ingredients
        @categories = IngredientCategory.ordered
        scope = filtered_ingredients
        @counts = {
          "all" => scope.count,
          "everywhere" => scope.where(all_locations: true).count,
          "limited" => scope.where(all_locations: false).count
        }
        scope = scope.where(all_locations: true) if @availability == "everywhere"
        scope = scope.where(all_locations: false) if @availability == "limited"
        @ingredients = scope
          .includes(:ingredient_category, :restricted_locations)
          .order(Arel.sql("#{sort_column} #{@direction == 'desc' ? 'DESC' : 'ASC'}"))
          .to_a
      end

      def filtered_ingredients
        scope = Ingredient.all
        scope = scope.active if @status == "active"
        scope = scope.where(active: false) if @status == "inactive"
        scope = scope.where(ingredient_category_id: @category_id) if @category_id
        if @query.present?
          term = "%#{Ingredient.sanitize_sql_like(@query.downcase)}%"
          scope = scope.where(
            "LOWER(ingredients.name) LIKE :term OR LOWER(ingredients.code) LIKE :term", term: term
          )
        end
        scope
      end

      def sort_column
        @sort == "code" ? "ingredients.code" : "ingredients.name"
      end

      def apply_changes
        active_ids = @locations.map { |loc| loc.id.to_s }
        ingredients = Ingredient.where(id: submitted_rows.keys)
          .includes(:restricted_locations, :company)
          .index_by { |ingredient| ingredient.id.to_s }
        updated = 0
        failures = []

        submitted_rows.each do |id, entry|
          ingredient = ingredients[id.to_s]
          next if ingredient.nil? || !entry.is_a?(Hash)
          next unless entry.key?("all_locations")

          begin
            updated += 1 if save_availability(ingredient, entry, active_ids)
          rescue ActiveRecord::RecordInvalid => e
            failures << e.record
          end
        end

        if failures.any?
          flash[:alert] = t(
            "inventory.ingredient_availabilities.save_failed",
            details: failures.map { |record| "#{record.name}: #{record.errors.full_messages.to_sentence}" }.to_sentence
          )
        end
        updated
      end

      # True when this row's effective scope changed. "All locations" is not the
      # same as every box ticked: it also covers locations created later, so
      # turning it on leaves any previously saved subset in place (the edit form
      # ignores that subset until the flag is turned off again). Assignments to
      # inactive locations are kept — this grid only lists active ones.
      def save_availability(ingredient, entry, active_ids)
        new_all = ActiveModel::Type::Boolean.new.cast(entry["all_locations"])
        current_ids = ingredient.restricted_locations.map { |loc| loc.id.to_s }
        inactive_kept = current_ids - active_ids
        current_active = current_ids & active_ids
        allowed = Array(entry["location_ids"]).map(&:to_s).reject(&:blank?) & active_ids

        return false if new_all && ingredient.all_locations?
        return false if !new_all && !ingredient.all_locations? && current_active.sort == allowed.sort

        before_label = scope_label(ingredient.all_locations?, current_active)
        after_ids = new_all ? current_active : allowed
        after_label = scope_label(new_all, after_ids)
        changes = {}
        if ingredient.all_locations? != new_all
          changes["all_locations"] = [ingredient.all_locations, new_all]
        end
        changes["location_access"] = [before_label, after_label] if before_label != after_label

        Ingredient.transaction do
          ingredient.without_auditing do
            if new_all
              ingredient.update!(all_locations: true)
            else
              ingredient.update!(all_locations: false, restricted_location_ids: allowed + inactive_kept)
            end
          end
          write_location_audit(ingredient, changes)
        end
        true
      end

      def scope_label(all_locations, active_location_ids)
        return I18n.t("inventory.ingredient_availabilities.scope_all") if all_locations

        names = @locations.select { |loc| active_location_ids.include?(loc.id.to_s) }.map(&:name)
        names.presence&.join(" · ") || I18n.t("inventory.ingredient_availabilities.scope_none")
      end

      def write_location_audit(ingredient, changes)
        return if changes.blank?

        next_version = (ingredient.audits.maximum(:version) || 0) + 1
        Audited::Audit.create!(
          auditable: ingredient,
          associated: ingredient.company,
          user: current_user,
          action: "location_access_changed",
          audited_changes: changes,
          version: next_version
        )
      end

      def submitted_rows
        raw = params[:availabilities]
        return {} unless raw.respond_to?(:to_unsafe_h)

        raw.to_unsafe_h
      end
    end
  end
end
