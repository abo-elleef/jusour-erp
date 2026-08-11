# frozen_string_literal: true

require "csv"

module Legacy
  # Parses a one-day sales export from the restaurant's old POS (headerless CSV
  # exported from Excel) and upserts customers into Saqr.
  #
  # The export is order-centric. Useful customer fields per order row:
  #   col 0  — phone (often blank)
  #   col 4  — "عملاء- {name}"
  #   col 32 — legacy AR account code (e.g. 01/1/3/10894)
  #
  # Walk-in placeholders ("العميل النقدي", "عميل طاولة") are skipped. Saqr
  # requires email or phone, so named customers without a valid Egyptian mobile
  # are only imported when +include_name_only+ is true (synthetic email).
  class OldPosOrdersCustomerImport
    SKIP_NAMES = [
      "العميل النقدي",
      "عميل طاولة"
    ].freeze

    NAME_PREFIX = /\Aعملاء\s*-\s*/u
    EG_MOBILE_IN_TEXT = /(?<!\d)(?:\+?20)?0?(1[0125]\d{8})(?!\d)/

    Candidate = Struct.new(
      :name, :phone, :email, :legacy_account_code, :order_count,
      :source_phones, keyword_init: true
    )

    Result = Struct.new(
      :candidates, :created, :updated, :skipped_existing, :failed, :skipped_rows,
      keyword_init: true
    )

    def initialize(path:, company:, dry_run: true, include_name_only: false, io: nil)
      @path = path&.to_s
      @io = io
      @company = company
      @dry_run = dry_run
      @include_name_only = include_name_only
    end

    def call
      candidates = parse_candidates
      created = []
      updated = []
      skipped_existing = []
      failed = []

      Current.company = @company

      candidates.each do |candidate|
        unless importable?(candidate)
          next
        end

        begin
          record, status = upsert_customer(candidate)
          case status
          when :created then created << [record, candidate]
          when :updated then updated << [record, candidate]
          when :skipped_existing then skipped_existing << [record, candidate]
          end
        rescue StandardError => e
          failed << [candidate, e.message]
        end
      end

      Result.new(
        candidates: candidates,
        created: created,
        updated: updated,
        skipped_existing: skipped_existing,
        failed: failed,
        skipped_rows: @skipped_rows
      )
    ensure
      Current.company = nil
    end

    # Public for dry-run reporting / specs.
    def parse_candidates
      @skipped_rows = 0
      by_key = {}

      each_csv_row do |row|
        next if row.nil? || row.all? { |c| c.to_s.strip.empty? }

        raw_name = row[4].to_s
        name = clean_name(raw_name)
        if name.blank? || SKIP_NAMES.include?(name)
          @skipped_rows += 1
          next
        end

        phone = normalize_egyptian_mobile(row[0].to_s)
        phone ||= extract_egyptian_mobile(raw_name)
        account = row[32].to_s.strip.presence
        key = phone.presence || account.presence || name.downcase

        candidate = by_key[key] ||= Candidate.new(
          name: name,
          phone: phone,
          email: nil,
          legacy_account_code: account,
          order_count: 0,
          source_phones: []
        )
        candidate.order_count += 1
        candidate.source_phones << phone if phone
        candidate.phone ||= phone
        candidate.legacy_account_code ||= account
        candidate.name = prefer_name(candidate.name, name)
      end

      by_key.each_value do |candidate|
        if candidate.phone.blank? && @include_name_only && candidate.legacy_account_code.present?
          candidate.email = synthetic_email(candidate.legacy_account_code)
        end
        # Names that are only digits/noise aren't useful once we have a phone.
        if candidate.phone.present? && mostly_numeric_name?(candidate.name)
          candidate.name = nil
        end
      end

      by_key.values.sort_by { |c| [-c.order_count, c.name.to_s, c.phone.to_s] }
    end

    private

    def each_csv_row(&block)
      if @io
        CSV.new(@io, encoding: "bom|utf-8").each(&block)
      else
        CSV.foreach(@path, encoding: "bom|utf-8", &block)
      end
    end

    def importable?(candidate)
      candidate.phone.present? || (@include_name_only && candidate.email.present?)
    end

    def upsert_customer(candidate)
      existing = find_existing(candidate)

      if existing
        attrs = {}
        attrs[:name] = candidate.name if candidate.name.present? && existing.name.blank?
        if attrs.any? && !@dry_run
          existing.update!(attrs)
          return [existing, :updated]
        end
        return [existing, attrs.any? && @dry_run ? :updated : :skipped_existing]
      end

      record = Customer.new(
        company: @company,
        name: candidate.name,
        phone: candidate.phone,
        email: candidate.email
      )
      record.save! unless @dry_run
      [record, :created]
    end

    def find_existing(candidate)
      scope = Customer.unscoped_by_company.where(company_id: @company.id)
      if candidate.phone.present?
        found = scope.where(phone: candidate.phone)
          .or(scope.where(phone_secondary: candidate.phone))
          .first
        return found if found
      end
      return nil if candidate.email.blank?

      scope.find_by(email: candidate.email)
    end

    def clean_name(raw)
      name = raw.to_s.sub(NAME_PREFIX, "").strip
      name = name.gsub(/[_\.]+/, " ")
      name = name.gsub(EG_MOBILE_IN_TEXT, "")
      name = name.gsub(/\s+/, " ").strip
      name = name.gsub(/\A[\s.\-+]+|[\s.\-+]+\z/, "")
      name.presence
    end

    def prefer_name(current, incoming)
      return incoming if current.blank?
      return current if incoming.blank?
      return incoming if mostly_numeric_name?(current) && !mostly_numeric_name?(incoming)
      return current if mostly_numeric_name?(incoming) && !mostly_numeric_name?(current)

      incoming.length >= current.length ? incoming : current
    end

    def mostly_numeric_name?(name)
      s = name.to_s.gsub(/\s+/, "")
      return true if s.blank?

      digits = s.gsub(/\D/, "")
      digits.length >= (s.length * 0.6)
    end

    def normalize_egyptian_mobile(value)
      digits = value.to_s.gsub(/\D/, "")
      return nil if digits.blank?

      digits = digits.delete_prefix("20") if digits.start_with?("20") && digits.length >= 12
      digits = "0#{digits}" if digits.match?(/\A1[0125]\d{8}\z/)
      return digits if digits.match?(/\A01[0125]\d{8}\z/)

      nil
    end

    def extract_egyptian_mobile(text)
      match = text.to_s.gsub(/\s+/, "").match(EG_MOBILE_IN_TEXT)
      return nil unless match

      normalize_egyptian_mobile("0#{match[1]}")
    end

    def synthetic_email(account_code)
      slug = account_code.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      "legacy-#{slug}@import.invalid"
    end
  end
end
