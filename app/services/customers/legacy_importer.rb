# frozen_string_literal: true

module Customers
  # Imports customers exported from the previous system.
  #
  # Expects an array of row hashes with string keys:
  #   legacy_code, name, phone1, phone2, address, notes
  #
  # Cleans and de-dupes to fit the current schema:
  #   * name  -> name (junk like "...", "00" is nulled)
  #   * phone1 -> phone, phone2 -> phone_secondary (invalid/duplicate values dropped;
  #     phone uniqueness is enforced across BOTH columns, so we track one global set)
  #   * address -> a default CustomerAddress
  #   * notes  -> notes
  #   * legacy_code -> legacy_code (used as the idempotency key; duplicated source
  #     codes are treated as unreliable and nulled)
  #
  # A customer with no usable phone (and no email in the source) can't satisfy the
  # model's email-or-phone rule, so it is skipped and reported.
  #
  # dry_run: true builds and validates everything inside a rolled-back transaction,
  # so the report reflects real validation/uniqueness results without persisting.
  class LegacyImporter
    Result = Struct.new(
      :created, :updated, :skipped_no_contact, :phone_conflicts,
      :addresses_created, :notes_set, :legacy_deduped, :errors, :skipped_rows, :dry_run,
      keyword_init: true
    ) do
      def total_touched = created + updated
    end

    JUNK_NAME = /\A[\s0.\-_]*\z/ # only spaces/zeros/dots/dashes

    def initialize(rows:, company:, dry_run: true)
      @rows = rows
      @company = company
      @dry_run = dry_run
      @result = Result.new(
        created: 0, updated: 0, skipped_no_contact: 0, phone_conflicts: 0,
        addresses_created: 0, notes_set: 0, legacy_deduped: 0,
        errors: [], skipped_rows: [], dry_run: dry_run
      )
      # Source legacy codes that appear more than once are unreliable keys.
      @dup_codes = @rows.map { |r| r["legacy_code"].to_s.strip }
        .reject(&:blank?).tally.select { |_, n| n > 1 }.keys.to_set
      # Phone values already taken (existing rows + ones we assign this run),
      # covering both columns since uniqueness spans them.
      @used_phones = Set.new(
        Customer.where(company: @company).pluck(:phone, :phone_secondary).flatten.compact_blank
      )
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
      name = clean_name(row["name"])
      legacy = clean_legacy(row["legacy_code"])

      p1 = normalize_phone(row["phone1"])
      p2 = normalize_phone(row["phone2"])
      p2 = nil if p2 && p2 == p1

      # Resolve any existing customer first (idempotent re-imports) so it can keep
      # its own phone numbers instead of colliding with itself.
      customer = find_or_init(legacy, p1)
      new_record = customer.new_record?
      own = new_record ? [] : [customer.phone, customer.phone_secondary].compact_blank

      phone  = take_phone(p1, own)
      phone2 = take_phone(p2, own)
      # The model requires a PRIMARY phone (a secondary alone doesn't satisfy the
      # email-or-phone rule), so promote a surviving secondary when primary is gone.
      if phone.blank? && phone2.present?
        phone = phone2
        phone2 = nil
      end

      # No phone and no email means the model's email-or-phone rule can't pass.
      if phone.blank?
        @result.skipped_no_contact += 1
        @result.skipped_rows << row
        return
      end

      customer.name ||= name
      customer.name = name if name.present?
      customer.phone = phone if phone.present?
      customer.phone_secondary = phone2 if phone2.present?
      customer.legacy_code = legacy if legacy.present?

      notes = row["notes"].to_s.strip
      if notes.present?
        customer.notes = notes
        @result.notes_set += 1
      end

      attach_address(customer, row["address"])

      if customer.save
        new_record ? (@result.created += 1) : (@result.updated += 1)
      else
        @result.errors << { row: index + 2, name: name || phone, messages: customer.errors.full_messages }
      end
    end

    # Match an already-imported customer by legacy code (the reliable key), or by
    # the row's PRIMARY phone against an existing primary phone. Deliberately does
    # not match on secondary phones, which would merge unrelated customers.
    def find_or_init(legacy, primary_phone)
      scope = Customer.where(company: @company)
      existing =
        (legacy.present? && scope.find_by(legacy_code: legacy)) ||
        (primary_phone.present? && scope.find_by(phone: primary_phone))
      existing || Customer.new(company: @company)
    end

    def take_phone(phone, own = [])
      return nil if phone.blank?
      return phone if own.include?(phone) # the customer's own number — already reserved

      if @used_phones.include?(phone)
        @result.phone_conflicts += 1
        return nil
      end
      @used_phones << phone
      phone
    end

    def attach_address(customer, raw)
      addr = raw.to_s.strip
      return if addr.length < 4
      return if customer.addresses.any? { |a| a.address.to_s.strip == addr }

      customer.addresses.build(address: addr, is_default: customer.addresses.empty?)
      @result.addresses_created += 1
    end

    def clean_name(raw)
      name = raw.to_s.strip
      return nil if name.length < 2 || JUNK_NAME.match?(name)

      name
    end

    def clean_legacy(raw)
      code = raw.to_s.strip
      return nil if code.blank?

      if @dup_codes.include?(code)
        @result.legacy_deduped += 1
        return nil
      end
      code
    end

    # Keep digits only; Egyptian mobiles are 11 digits, landlines 7-10. Reject
    # anything too short (e.g. "0") or implausibly long.
    def normalize_phone(raw)
      digits = raw.to_s.gsub(/\D/, "")
      return nil if digits.length < 7 || digits.length > 15

      digits
    end

  end
end
