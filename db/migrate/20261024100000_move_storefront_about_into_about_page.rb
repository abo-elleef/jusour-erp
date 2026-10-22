# frozen_string_literal: true

# The company story now lives only in the "About us" info page. Copy each
# storefront's settings about text (English and Arabic) into that page's
# rich-text bodies and publish it, without overwriting anything an admin
# already wrote there. Raw SQL on purpose: migrations must not depend on app
# models.
class MoveStorefrontAboutIntoAboutPage < ActiveRecord::Migration[7.1]
  def up
    storefronts = select_all(<<~SQL.squish)
      SELECT id, company_id, about, about_ar FROM storefronts
      WHERE COALESCE(about, '') <> '' OR COALESCE(about_ar, '') <> ''
    SQL

    storefronts.each do |row|
      page_id = select_value(<<~SQL.squish)
        SELECT id FROM storefront_pages WHERE storefront_id = #{quote(row['id'])} AND slot = 'about'
      SQL
      page_id ||= select_value(<<~SQL.squish)
        INSERT INTO storefront_pages (company_id, storefront_id, slot, enabled, title, title_ar, created_at, updated_at)
        VALUES (#{quote(row['company_id'])}, #{quote(row['id'])}, 'about', TRUE, '', '', NOW(), NOW())
        RETURNING id
      SQL

      { "body" => row["about"], "body_ar" => row["about_ar"] }.each do |name, text|
        next if text.to_s.strip.empty?

        existing = select_value(<<~SQL.squish)
          SELECT 1 FROM action_text_rich_texts
          WHERE record_type = 'StorefrontPage' AND record_id = #{quote(page_id)} AND name = #{quote(name)}
        SQL
        next if existing

        execute(<<~SQL.squish)
          INSERT INTO action_text_rich_texts (name, body, record_type, record_id, created_at, updated_at)
          VALUES (#{quote(name)}, #{quote(plain_text_to_html(text))}, 'StorefrontPage', #{quote(page_id)}, NOW(), NOW())
        SQL
      end
    end
  end

  def down
    # The copied pages are ordinary content now; nothing to undo.
  end

  private

  # Blank-line-separated paragraphs become <div>s, single newlines <br>s —
  # the same shape Trix produces.
  def plain_text_to_html(text)
    text.to_s.gsub("\r\n", "\n").strip.split(/\n\s*\n/).map do |paragraph|
      "<div>#{ERB::Util.html_escape(paragraph.strip).gsub("\n", '<br>')}</div>"
    end.join
  end
end
