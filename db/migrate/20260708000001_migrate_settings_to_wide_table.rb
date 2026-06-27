# frozen_string_literal: true

class MigrateSettingsToWideTable < ActiveRecord::Migration[7.1]
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

    # Backfill one row per company from the old EAV settings table
    integer_keys = %w[
      loyalty_earn_rate loyalty_redeem_threshold loyalty_redeem_value_cents
      print_agent_port print_code_page
    ]

    Company.find_each do |company|
      old_rows = execute(
        sanitize_sql(["SELECT key, value FROM settings WHERE company_id = ?", company.id])
      ).to_a

      kv = old_rows.each_with_object({}) { |r, h| h[r["key"]] = r["value"] }

      row_attrs = {
        company_id:                  company.id,
        loyalty_earn_rate:           cast(kv, "loyalty_earn_rate",          :int, 1),
        loyalty_redeem_threshold:    cast(kv, "loyalty_redeem_threshold",   :int, 100),
        loyalty_redeem_value_cents:  cast(kv, "loyalty_redeem_value_cents", :int, 500),
        restaurant_name:             kv["restaurant_name"],
        print_routing:               kv["print_routing"]    || "client",
        print_agent_port:            cast(kv, "print_agent_port",   :int, 9310),
        print_agent_token:           kv["print_agent_token"] || "",
        print_encoding:              kv["print_encoding"]    || "utf-8",
        print_code_page:             cast(kv, "print_code_page",    :int, 22),
        arabic_font_path:            kv["arabic_font_path"]  || "",
        receipt_logo_url:            kv["receipt_logo_url"]  || "",
        receipt_footer_text:         kv["receipt_footer_text"] || "",
        created_at:                  Time.current,
        updated_at:                  Time.current
      }

      execute(sanitize_sql([<<~SQL, row_attrs]))
        INSERT INTO company_settings (
          id, company_id,
          loyalty_earn_rate, loyalty_redeem_threshold, loyalty_redeem_value_cents,
          restaurant_name, print_routing, print_agent_port, print_agent_token,
          print_encoding, print_code_page, arabic_font_path, receipt_logo_url,
          receipt_footer_text, created_at, updated_at
        ) VALUES (
          gen_random_uuid(), :company_id,
          :loyalty_earn_rate, :loyalty_redeem_threshold, :loyalty_redeem_value_cents,
          :restaurant_name, :print_routing, :print_agent_port, :print_agent_token,
          :print_encoding, :print_code_page, :arabic_font_path, :receipt_logo_url,
          :receipt_footer_text, :created_at, :updated_at
        )
      SQL
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

    # Restore EAV rows from wide table
    execute(<<~SQL)
      INSERT INTO settings (id, company_id, key, value, created_at, updated_at)
      SELECT gen_random_uuid(), company_id, col.key, col.val::text, NOW(), NOW()
      FROM company_settings
      CROSS JOIN LATERAL (
        VALUES
          ('loyalty_earn_rate',          loyalty_earn_rate::text),
          ('loyalty_redeem_threshold',   loyalty_redeem_threshold::text),
          ('loyalty_redeem_value_cents', loyalty_redeem_value_cents::text),
          ('restaurant_name',            restaurant_name),
          ('print_routing',              print_routing),
          ('print_agent_port',           print_agent_port::text),
          ('print_agent_token',          print_agent_token),
          ('print_encoding',             print_encoding),
          ('print_code_page',            print_code_page::text),
          ('arabic_font_path',           arabic_font_path),
          ('receipt_logo_url',           receipt_logo_url),
          ('receipt_footer_text',        receipt_footer_text)
      ) AS col(key, val)
      WHERE col.val IS NOT NULL AND col.val <> ''
    SQL

    drop_table :company_settings
  end

  private

  def cast(kv, key, type, default)
    val = kv[key]
    return default if val.nil? || val.strip.empty?
    type == :int ? val.to_i : val
  end
end
