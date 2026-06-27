# frozen_string_literal: true

class MigrateSettingsToWideTable < ActiveRecord::Migration[7.1]
  # Temporary AR classes so we can use Ruby objects without touching
  # the real models (which may have validations/scopes that don't apply here).
  class MigrationCompany < ActiveRecord::Base
    self.table_name = "companies"
  end

  class MigrationSetting < ActiveRecord::Base
    self.table_name = "settings"
  end

  class MigrationCompanySetting < ActiveRecord::Base
    self.table_name = "company_settings"
  end

  INTEGER_KEYS = %w[
    loyalty_earn_rate loyalty_redeem_threshold loyalty_redeem_value_cents
    print_agent_port print_code_page
  ].freeze

  STRING_KEYS = %w[
    restaurant_name print_routing print_agent_token print_encoding
    arabic_font_path receipt_logo_url receipt_footer_text
  ].freeze

  DEFAULTS = {
    "loyalty_earn_rate"          => 1,
    "loyalty_redeem_threshold"   => 100,
    "loyalty_redeem_value_cents" => 500,
    "restaurant_name"            => nil,
    "print_routing"              => "client",
    "print_agent_port"           => 9310,
    "print_agent_token"          => "",
    "print_encoding"             => "utf-8",
    "print_code_page"            => 22,
    "arabic_font_path"           => "",
    "receipt_logo_url"           => "",
    "receipt_footer_text"        => ""
  }.freeze

  def up
    create_table :company_settings, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.integer  :loyalty_earn_rate,          default: 1,         null: false
      t.integer  :loyalty_redeem_threshold,   default: 100,       null: false
      t.integer  :loyalty_redeem_value_cents, default: 500,       null: false
      t.string   :restaurant_name
      t.string   :print_routing,              default: "client",  null: false
      t.integer  :print_agent_port,           default: 9310,      null: false
      t.string   :print_agent_token,          default: "",        null: false
      t.string   :print_encoding,             default: "utf-8",   null: false
      t.integer  :print_code_page,            default: 22,        null: false
      t.string   :arabic_font_path,           default: "",        null: false
      t.string   :receipt_logo_url,           default: "",        null: false
      t.text     :receipt_footer_text,        default: "",        null: false
      t.timestamps
    end

    MigrationCompany.find_each do |company|
      kv = MigrationSetting
        .where(company_id: company.id)
        .each_with_object({}) { |r, h| h[r.key] = r.value }

      attrs = DEFAULTS.keys.each_with_object({}) do |key, h|
        raw = kv[key]
        h[key] = if raw.present?
          INTEGER_KEYS.include?(key) ? raw.to_i : raw
        else
          DEFAULTS[key]
        end
      end

      MigrationCompanySetting.create!(attrs.merge(company_id: company.id))
    end

    drop_table :settings
  end

  def down
    create_table :settings, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :key,   null: false
      t.text   :value
      t.timestamps
    end
    add_index :settings, %i[company_id key], unique: true

    MigrationCompanySetting.find_each do |cs|
      (INTEGER_KEYS + STRING_KEYS).each do |key|
        val = cs.public_send(key)
        next if val.nil?
        MigrationSetting.create!(
          company_id: cs.company_id,
          key:        key,
          value:      val.to_s
        )
      end
    end

    drop_table :company_settings
  end
end
