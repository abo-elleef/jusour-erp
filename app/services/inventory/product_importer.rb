# frozen_string_literal: true

module Inventory
  # Imports products (as Ingredients) from the previous system.
  #
  # Row hash (string keys): code, name, unit_raw, cost, selling_price
  #   * code  -> ingredient code (idempotency key; deduped per company)
  #   * name  -> name
  #   * unit_raw -> mapped to a company unit (Arabic piece names -> "pieces")
  #   * cost  -> cost_per_unit_cents (currency in the file)
  #   * selling_price -> selling_price_cents
  #
  # Stock quantities are NOT imported (opening stock needs locations/batches — a
  # separate step). New products enter at 0 on-hand. dry_run rolls back.
  class ProductImporter
    DEFAULT_CATEGORY = "Imported products"
    UNIT_MAP = { "قطعة" => "pieces", "الوحدة" => "pieces", "piece" => "pieces", "pcs" => "pieces" }.freeze

    Result = Struct.new(:created, :updated, :skipped_no_name, :errors, :dry_run, keyword_init: true)

    def initialize(rows:, company:, dry_run: true)
      @rows = rows
      @company = company
      @dry_run = dry_run
      @result = Result.new(created: 0, updated: 0, skipped_no_name: 0, errors: [], dry_run: dry_run)
    end

    def call
      previous = Current.company
      Current.company = @company
      ActiveRecord::Base.transaction do
        @rows.each_with_index { |row, i| process(row, i) }
        raise ActiveRecord::Rollback if @dry_run
      end
      @result
    ensure
      Current.company = previous
    end

    private

    def process(row, index)
      name = row["name"].to_s.strip
      if name.blank?
        @result.skipped_no_name += 1
        return
      end

      code = row["code"].to_s.strip
      ingredient = find_or_init(code)
      new_record = ingredient.new_record?

      ingredient.name = name
      ingredient.unit = mapped_unit(row["unit_raw"])
      ingredient.ingredient_category ||= default_category
      ingredient.code = code if code.present?
      ingredient.cost_per_unit_cents = to_cents(row["cost"]) if row["cost"].to_s.strip.present?
      ingredient.selling_price_cents = to_cents(row["selling_price"]) if row["selling_price"].to_s.strip.present?

      if ingredient.save
        new_record ? (@result.created += 1) : (@result.updated += 1)
      else
        @result.errors << { row: index + 2, name: name, messages: ingredient.errors.full_messages }
      end
    end

    def find_or_init(code)
      scope = Ingredient.where(company: @company)
      (code.present? && scope.find_by(code: code)) || Ingredient.new(company: @company)
    end

    def mapped_unit(raw)
      key = raw.to_s.strip
      UNIT_MAP[key] || (@company.unit_names.include?(key) ? key : "pieces")
    end

    def default_category
      @default_category ||= IngredientCategory.where(company: @company)
        .find_or_create_by!(name: DEFAULT_CATEGORY)
    end

    def to_cents(value)
      (BigDecimal(value.to_s.strip.presence || "0") * 100).round
    rescue ArgumentError
      0
    end
  end
end
