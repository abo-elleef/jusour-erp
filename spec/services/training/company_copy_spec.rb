# frozen_string_literal: true

require "rails_helper"

RSpec.describe Training::CompanyCopy do
  let(:source) { create(:company, slug: "source-co", name: "Source Co") }

  # A small but representative catalogue: two locations so transfers are
  # possible, an ingredient with an alternate unit, a menu item with a recipe,
  # and a supplier wired to its own AP treasury.
  let!(:catalogue) do
    Current.company = source

    kitchen = create(:location, :central_kitchen, company: source, name: "Kitchen")
    branch  = create(:location, company: source, name: "Branch")
    category = create(:ingredient_category, company: source, name: "Proteins")
    ingredient = create(:ingredient, company: source, ingredient_category: category,
      name: "Chicken", quantity_on_hand: 40, reorder_threshold: 5, cost_per_unit_cents: 450)

    alternate = Unit.unscoped.where(company_id: source.id).where.not(name: ingredient.unit).first
    IngredientUnit.create!(company: source, ingredient: ingredient,
      unit: alternate.name, base_units_per_unit: 10)

    menu_category = Category.create!(company: source, name: "Mains", position: 1)
    menu_item = MenuItem.create!(company: source, category: menu_category, name: "Grilled Chicken",
      base_price_cents: 9_000, code: "MAIN-1")
    Recipe.create!(menu_item: menu_item, ingredient: ingredient, quantity_used: 2, unit: ingredient.unit)

    supplier = Supplier.create!(company: source, name: "Metro Foods", lead_time_days: 2)
    ap = Treasury.create!(company: source, name: "Metro AP", treasury_type: "supplier_ap",
      supplier: supplier, balance_cents: 250_000, opening_balance_cents: 100_000)
    supplier.update!(treasury_id: ap.id)
    SupplierIngredient.create!(supplier: supplier, ingredient: ingredient, price_cents: 450, preferred: true)

    Treasury.create!(company: source, name: "Main Safe", treasury_type: "safe",
      balance_cents: 500_000, opening_balance_cents: 500_000, is_default: true)
    ExpenseCategory.create!(company: source, name: "Rent", category_type: "rent", position: 1)
    IncomeCategory.create!(company: source, name: "POS Sales", category_type: "sales", position: 1)
    TaxRate.create!(company: source, name: "VAT", tax_category: "food", rate: 0.14, active: true)
    LocationMenuItem.create!(location: branch, menu_item: menu_item, available: true)
    IngredientLocation.create!(ingredient: ingredient, location: kitchen,
      quantity_on_hand: 40, reorder_threshold: 7, max_quantity: 90)

    template = StockTransferTemplate.new(company: source, name: "Daily top-up", active: true,
      default_from_location_id: kitchen.id, default_to_location_id: branch.id)
    template.stock_transfer_template_lines.build(ingredient: ingredient, unit: ingredient.unit,
      default_quantity: 6)
    template.save!

    { kitchen: kitchen, branch: branch, ingredient: ingredient, menu_item: menu_item,
      supplier: supplier, ap: ap, template: template }
  end

  # The people and history that must NOT cross over.
  let!(:noise) do
    Current.company = source
    staff = create(:user, :manager, company: source, name: "Real Employee",
      email: "real@source.test", monthly_salary_cents: 900_000)
    customer = Customer.create!(company: source, name: "Real Customer", phone: "01000000000")
    { staff: staff, customer: customer }
  end

  before { Current.company = source }
  after { Current.reset }

  def copy(**overrides)
    described_class.call(**{ source_slug: "source-co", slug: "training-01" }.merge(overrides))
  end

  describe "validation" do
    it "refuses a slug that already exists" do
      expect { copy(slug: "source-co") }.to raise_error(ArgumentError, /differ from SOURCE_SLUG/)
    end

    it "refuses an unknown source" do
      expect { copy(source_slug: "nope") }.to raise_error(ArgumentError, /No company with slug/)
    end

    it "refuses a malformed slug" do
      expect { copy(slug: "Training 01") }.to raise_error(ArgumentError, /must match/)
    end

    it "refuses an unknown mate role" do
      expect { copy(mate_role: "wizard") }.to raise_error(ArgumentError, /MATE_ROLE/)
    end

    it "leaves nothing behind when the copy fails part-way" do
      allow(TaxRate).to receive(:new).and_raise(ActiveRecord::RecordInvalid.new(TaxRate.new))

      expect { copy }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Company.unscoped.find_by(slug: "training-01")).to be_nil
    end
  end

  describe "the copied company" do
    let(:result) { copy }
    let(:target) { result.company }

    it "inherits the source's profile but gets its own identity" do
      expect(target.slug).to eq("training-01")
      expect(target.name).to eq("Source Co — Training")
      expect(target.business_type).to eq(source.business_type)
      expect(target.currency).to eq(source.currency)
      expect(target.id).not_to eq(source.id)
    end

    it "copies the catalogue" do
      scoped = ->(model) { model.unscoped.where(company_id: target.id) }

      expect(scoped.call(Location).pluck(:name)).to match_array(%w[Kitchen Branch])
      expect(scoped.call(Ingredient).pluck(:name)).to eq(["Chicken"])
      expect(scoped.call(MenuItem).pluck(:name)).to eq(["Grilled Chicken"])
      expect(scoped.call(Supplier).pluck(:name)).to eq(["Metro Foods"])
      expect(scoped.call(ExpenseCategory).pluck(:name)).to include("Rent")
      expect(scoped.call(TaxRate).pluck(:name)).to eq(["VAT"])
    end

    it "rewires child rows onto the copied parents, never the source's" do
      ingredient = Ingredient.unscoped.find_by(company_id: target.id)
      menu_item = MenuItem.unscoped.find_by(company_id: target.id)
      recipe = Recipe.where(menu_item_id: menu_item.id).first

      expect(ingredient.id).not_to eq(catalogue[:ingredient].id)
      expect(recipe.ingredient_id).to eq(ingredient.id)
      expect(menu_item.category_id).to eq(Category.unscoped.find_by(company_id: target.id).id)
      expect(ingredient.unit_id).to eq(Unit.unscoped.find_by(company_id: target.id, name: ingredient.unit).id)
    end

    it "resolves the supplier/treasury circular reference both ways" do
      supplier = Supplier.unscoped.find_by(company_id: target.id)
      ap = Treasury.unscoped.find_by(company_id: target.id, treasury_type: "supplier_ap")

      expect(supplier.treasury_id).to eq(ap.id)
      expect(ap.supplier_id).to eq(supplier.id)
      expect(supplier.treasury_id).not_to eq(catalogue[:ap].id)
    end

    it "zeroes every treasury balance" do
      treasuries = Treasury.unscoped.where(company_id: target.id)
      # The safe and the supplier's AP sub-ledger, plus the drawer the owner
      # account creates for itself.
      drawer_ids = User.unscoped.where(company_id: target.id).pluck(:assigned_treasury_id)

      # The AP sub-ledger is named by SupplierApLedgerService rather than carrying
      # the source's own name for it — the hook builds it, we only map onto it.
      expect(treasuries.where.not(id: drawer_ids).pluck(:name))
        .to match_array(["Main Safe", "Metro Foods — AP"])
      expect(treasuries.pluck(:balance_cents).uniq).to eq([0])
      expect(treasuries.pluck(:opening_balance_cents).uniq).to eq([0])
    end

    it "keeps per-location par levels but not the shelf quantity" do
      row = IngredientLocation
        .where(location_id: Location.unscoped.where(company_id: target.id, location_type: "central_kitchen").select(:id))
        .first

      expect(row.reorder_threshold).to eq(7)
      expect(row.max_quantity).to eq(90)
    end

    it "copies templates with their lines intact" do
      template = StockTransferTemplate.unscoped.find_by(company_id: target.id)
      line = template.stock_transfer_template_lines.first

      expect(template).to be_active
      expect(template.default_from_location_id)
        .to eq(Location.unscoped.find_by(company_id: target.id, name: "Kitchen").id)
      expect(line.ingredient_id).to eq(Ingredient.unscoped.find_by(company_id: target.id).id)
      expect(line.default_quantity).to eq(6)
    end
  end

  describe "what must not cross over" do
    let(:result) { copy }
    let(:target) { result.company }

    it "copies no people and no history" do
      expect(Customer.unscoped.where(company_id: target.id)).to be_empty
      expect(Order.unscoped.where(company_id: target.id)).to be_empty
      expect(JournalEntry.unscoped.where(company_id: target.id)).to be_empty
      expect(VendorInvoice.unscoped.where(company_id: target.id)).to be_empty
      expect(PayrollAdvance.unscoped.where(company_id: target.id)).to be_empty
    end

    it "creates only training accounts, carrying no salary" do
      users = User.unscoped.where(company_id: target.id)

      expect(users.pluck(:email)).to eq(["owner@training-01.training"])
      expect(users.pluck(:monthly_salary_cents).uniq).to eq([0])
      expect(users.pluck(:email)).not_to include(noise[:staff].email)
    end

    it "does not copy a staff member's personal cash drawer" do
      personal = Treasury.unscoped.find(noise[:staff].assigned_treasury_id)

      expect(Treasury.unscoped.where(company_id: target.id).pluck(:name)).not_to include(personal.name)
    end

    it "leaves the source company completely untouched" do
      before_counts = {
        ingredients: Ingredient.unscoped.where(company_id: source.id).count,
        menu_items: MenuItem.unscoped.where(company_id: source.id).count,
        treasuries: Treasury.unscoped.where(company_id: source.id).count,
        users: User.unscoped.where(company_id: source.id).count
      }

      copy(slug: "training-02")

      expect(Ingredient.unscoped.where(company_id: source.id).count).to eq(before_counts[:ingredients])
      expect(MenuItem.unscoped.where(company_id: source.id).count).to eq(before_counts[:menu_items])
      expect(Treasury.unscoped.where(company_id: source.id).count).to eq(before_counts[:treasuries])
      expect(User.unscoped.where(company_id: source.id).count).to eq(before_counts[:users])
      expect(catalogue[:ingredient].reload.quantity_on_hand).to eq(40)
      expect(catalogue[:supplier].reload.treasury_id).to eq(catalogue[:ap].id)
    end

    it "does not copy the live print agent credential" do
      Current.company = source
      CompanySetting.unscoped.where(company_id: source.id)
        .first_or_create!(company_id: source.id)
        .update!(print_agent_token: "live-secret-token")

      target = copy(slug: "training-03").company
      setting = CompanySetting.unscoped.find_by(company_id: target.id)

      expect(setting.print_agent_token).to be_blank
      expect(setting.restaurant_name).to eq(target.name)
    end
  end

  describe "rows the source can no longer save" do
    # A base unit changed after the recipe was written leaves the recipe
    # referencing a unit the ingredient no longer offers. It is already invalid
    # in the source; it just never gets re-saved there.
    before do
      Current.company = source
      stale = Unit.unscoped.where(company_id: source.id)
        .where.not(name: catalogue[:ingredient].unit).last
      Recipe.where(menu_item_id: catalogue[:menu_item].id)
        .update_all(unit_id: stale.id)
    end

    it "reports the row instead of aborting the whole company" do
      result = copy

      expect(result.company).to be_persisted
      expect(result.skipped.map { |r| r[:model] }).to eq([:recipes])
      expect(result.skipped.first[:reason]).to match(/no longer one of the ingredient's units/)
      expect(result.counts[:recipes_skipped]).to eq(1)
    end

    it "names the row by ingredient, parent and unit so it can be fixed at source" do
      label = copy.skipped.first[:label]

      expect(label).to include("Chicken")
      expect(label).to include("in Grilled Chicken")
    end

    it "copies everything else regardless" do
      target = copy.company

      expect(Recipe.where(menu_item_id: MenuItem.unscoped.where(company_id: target.id).select(:id))).to be_empty
      expect(MenuItem.unscoped.where(company_id: target.id).count).to eq(1)
      expect(Ingredient.unscoped.where(company_id: target.id).count).to eq(1)
    end
  end

  describe "accounts" do
    it "creates one login per mate, in the role given" do
      result = copy(mates: %w[ahmed sara], mate_role: "cashier", password: "Train2026!")
      users = User.unscoped.where(company_id: result.company.id)

      expect(result.mates).to eq(["ahmed@training-01.training", "sara@training-01.training"])
      expect(users.where(role: "cashier").pluck(:email))
        .to match_array(["ahmed@training-01.training", "sara@training-01.training"])
      expect(users.find_by(email: "ahmed@training-01.training").valid_password?("Train2026!")).to be(true)
    end

    it "gives every account its own cash drawer" do
      result = copy(mates: %w[ahmed])
      users = User.unscoped.where(company_id: result.company.id)

      drawer_ids = users.pluck(:assigned_treasury_id)
      expect(drawer_ids).to all(be_present)
      expect(drawer_ids.uniq.size).to eq(users.count)
    end
  end

  describe "opening stock" do
    it "stocks each ingredient at every location, with matching batches" do
      target = copy.company
      ingredient = Ingredient.unscoped.find_by(company_id: target.id)
      locations = Location.unscoped.where(company_id: target.id, active: true)
      batches = StockBatch.where(ingredient_id: ingredient.id)

      # reorder_threshold 5 x OPENING_STOCK_MULTIPLE 4 = 20 per location.
      expect(batches.count).to eq(locations.count)
      expect(batches.pluck(:quantity_remaining).uniq).to eq([20])
      expect(ingredient.quantity_on_hand).to eq(20 * locations.count)
      expect(IngredientLocation.where(ingredient_id: ingredient.id).pluck(:quantity_on_hand).uniq).to eq([20])
    end

    it "can be turned off, leaving everything at zero" do
      target = copy(opening_stock: false).company
      ingredient = Ingredient.unscoped.find_by(company_id: target.id)

      expect(ingredient.quantity_on_hand).to eq(0)
      expect(StockBatch.where(ingredient_id: ingredient.id)).to be_empty
      expect(IngredientLocation.where(ingredient_id: ingredient.id).pluck(:quantity_on_hand).uniq).to eq([0])
    end
  end
end
