# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261024100000_move_storefront_about_into_about_page")

# The about columns are ignored by the model now, so they're written with SQL
# here — the same way the migration reads them.
RSpec.describe MoveStorefrontAboutIntoAboutPage do
  let(:company) { create(:company, business_type: "distribution") }
  let(:storefront) { Storefront.create!(company: company) }

  before { Current.company = company }

  def set_about(english, arabic = "")
    Storefront.connection.execute(
      Storefront.sanitize_sql(["UPDATE storefronts SET about = ?, about_ar = ? WHERE id = ?", english, arabic, storefront.id])
    )
  end

  def migrate!
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  it "copies the settings about text into a published About us page, keeping paragraphs" do
    set_about("Vision: trusted products.\r\n\r\nMission: <science> & care.\nLine two.", "رؤيتنا")

    migrate!

    page = storefront.pages.sole
    expect(page).to have_attributes(slot: "about", enabled: true)
    expect(page.body.body.to_html).to include("<div>Vision: trusted products.</div>", "&lt;science&gt; &amp; care.<br>Line two.")
    expect(page.body_ar.to_plain_text).to eq("رؤيتنا")
  end

  it "never overwrites an About page someone already wrote" do
    set_about("Old settings text")
    storefront.pages.create!(slot: "about", enabled: false, body: "<p>Written on the page</p>")

    migrate!

    page = storefront.pages.sole
    expect(page.body.to_plain_text).to eq("Written on the page")
    expect(page).not_to be_enabled
  end

  it "leaves storefronts without about text alone, and can run twice" do
    storefront
    migrate!
    expect(StorefrontPage.count).to eq(0)

    set_about("Story")
    2.times { migrate! }
    expect(storefront.pages.count).to eq(1)
  end
end
