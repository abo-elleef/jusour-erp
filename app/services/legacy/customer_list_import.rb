# frozen_string_literal: true

require "csv"

module Legacy
  # Imports customers from `customers_export.csv` — the cleaned/merged output of
  # `build_customers_csv.py` (normal_customers.xlsx + vip_customers.xlsx from the
  # old POS/accounting system). One CSV row = one unique customer (already
  # deduped by phone across both source files); `address` / `extra_addresses`
  # become CustomerAddress records.
  #
  # Expected CSV header:
  #   name,phone,phone_secondary,address,extra_addresses,customer_type,
  #   phone_format_ok,legacy_balance_egp,legacy_ids,source_row_count
  #
  # NOTE: `customer_type` (normal/vip) and `legacy_balance_egp` are carried
  # through for reference only — the current `customers` table has no VIP flag
  # or legacy-balance column, so they are not written anywhere. Add a migration
  # first if you want either of those tracked going forward.
  class CustomerListImport
    Result = Struct.new(
      :created, :updated, :skipped_existing, :failed,
      :addresses_created, :rows_processed, :rows_skipped_bad_format,
      keyword_init: true
    )

    def initialize(path:, company:, dry_run: true, skip_bad_format: false)
      @path = path.to_s
      @company = company
      @dry_run = dry_run
      @skip_bad_format = skip_bad_format
    end

    def call
      created = []
      updated = []
      skipped_existing = []
      failed = []
      addresses_created = 0
      rows_processed = 0
      rows_skipped_bad_format = 0

      Current.company = @company

      CSV.foreach(@path, headers: true, encoding: "bom|utf-8") do |row|
        phone = row["phone"].to_s.strip
        next if phone.blank?

        if @skip_bad_format && row["phone_format_ok"].to_s.strip == "no"
          rows_skipped_bad_format += 1
          next
        end

        rows_processed += 1

        begin
          customer, status, addr_count = upsert_customer(row, phone)
          addresses_created += addr_count
          case status
          when :created then created << [customer, row]
          when :updated then updated << [customer, row]
          when :skipped_existing then skipped_existing << [customer, row]
          end
        rescue StandardError => e
          failed << [row, e.message]
        end
      end

      Result.new(
        created: created,
        updated: updated,
        skipped_existing: skipped_existing,
        failed: failed,
        addresses_created: addresses_created,
        rows_processed: rows_processed,
        rows_skipped_bad_format: rows_skipped_bad_format
      )
    ensure
      Current.company = nil
    end

    private

    def upsert_customer(row, phone)
      name = row["name"].to_s.strip.presence
      phone_secondary = row["phone_secondary"].to_s.strip.presence
      addresses = gather_addresses(row)

      scope = Customer.unscoped_by_company.where(company_id: @company.id)
      customer = scope.where(phone: phone).or(scope.where(phone_secondary: phone)).first
      is_new = customer.nil?
      customer ||= Customer.new(company: @company, phone: phone)

      changed = false
      if name.present? && customer.name.blank?
        customer.name = name
        changed = true
      end
      if phone_secondary.present? && customer.phone_secondary.blank? && phone_secondary != customer.phone
        customer.phone_secondary = phone_secondary
        changed = true
      end

      status = is_new ? :created : (changed ? :updated : :skipped_existing)

      if is_new || changed
        if @dry_run
          customer.valid?
          raise ActiveRecord::RecordInvalid, customer if customer.errors.any?
        else
          customer.save!
        end
      end

      addr_count = 0
      existing_texts = customer.persisted? ? customer.addresses.pluck(:address) : []
      addresses.each do |text|
        next if existing_texts.include?(text)

        if @dry_run
          addr = customer.addresses.build(address: text)
          addr.valid?
          raise ActiveRecord::RecordInvalid, addr if addr.errors.any?
        else
          customer.addresses.create!(address: text)
        end
        existing_texts << text
        addr_count += 1
      end

      [customer, status, addr_count]
    end

    def gather_addresses(row)
      list = [row["address"]]
      list += row["extra_addresses"].to_s.split(";")
      list.map { |a| a.to_s.strip }.reject(&:blank?).uniq
    end
  end
end
