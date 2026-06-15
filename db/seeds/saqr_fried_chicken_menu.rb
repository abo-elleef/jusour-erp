# frozen_string_literal: true
# Menu parsed from SAQR Fried Chicken printed menu (السنبلاوين).

module SaqrFriedChickenMenu
  BEEF_SIZE_GROUP = "حجم السندوتش - بيف"
  CHICKEN_SIZE_GROUP = "حجم السندوتش - دجاج"

  CATEGORIES = [
    { name: "سندوتشات بيف", position: 0 },
    { name: "سندوتشات دجاج", position: 1 },
    { name: "وجبات على السريع", position: 2 },
    { name: "وجبات فردية", position: 3 },
    { name: "وجبات عائلية", position: 4 },
    { name: "وجبات الأطفال", position: 5 },
    { name: "الإضافات", position: 6 }
  ].freeze

  # price: EGP (whole pounds). Modifiers use price_adjustment in EGP.
  ITEMS = [
    # — سندوتشات بيف (base = سنجل, دبل = +difference) —
    { category: "سندوتشات بيف", name: "أولد سكول", price: 110,
      description: "لحم بيف خالص، صوص بيج تاستي، مايونيز، طماطم، مخلل، خس",
      mods: [{ group: BEEF_SIZE_GROUP, required: true, mods: [["سنجل", 0], ["دبل", 35]] }] },
    { category: "سندوتشات بيف", name: "فولكانو", price: 110,
      description: "لحم بيف خالص، صوص لافا، هالابينو، مايونيز حار، مخلل، خس",
      mods: [{ group: BEEF_SIZE_GROUP, required: true, mods: [["سنجل", 0], ["دبل", 35]] }] },
    { category: "سندوتشات بيف", name: "كارمالايزد باربيكيو", price: 110,
      description: "لحم بيف خالص، بصل مكرمل، صوص باربيكيو، مايونيز، خس",
      mods: [{ group: BEEF_SIZE_GROUP, required: true, mods: [["سنجل", 0], ["دبل", 35]] }] },
    { category: "سندوتشات بيف", name: "مشروم مارفلز", price: 130,
      description: "لحم بيف خالص، صوص مشروم، صوص شيدر، مايونيز، مخلل، خس",
      mods: [{ group: BEEF_SIZE_GROUP, required: true, mods: [["سنجل", 0], ["دبل", 35]] }] },
    { category: "سندوتشات بيف", name: "ديسكفري", price: 140,
      description: "لحم بيف خالص، حلقات بصل، موتزريلا ستيكس، مايونيز، بيف مدخن، صوص بيج تاستي، مخلل، خس",
      mods: [{ group: BEEF_SIZE_GROUP, required: true, mods: [["سنجل", 0], ["دبل", 35]] }] },
    { category: "سندوتشات بيف", name: "كومبو (فرايز + كولا)", price: 45,
      description: "إضافة كومبو: بطاطس + كولا" },

    # — سندوتشات دجاج —
    { category: "سندوتشات دجاج", name: "أوريجينال", price: 110,
      description: "صدور دجاج فريش، صوص شيدر، مايونيز، مخلل، خس",
      mods: [{ group: CHICKEN_SIZE_GROUP, required: true, mods: [["سمول", 0], ["لارج", 20]] }] },
    { category: "سندوتشات دجاج", name: "سبايس كرافت", price: 110,
      description: "صدور دجاج فريش، صوص لافا، هالابينو، مايونيز حار، مخلل، صوص شيدر",
      mods: [{ group: CHICKEN_SIZE_GROUP, required: true, mods: [["سمول", 0], ["لارج", 20]] }] },
    { category: "سندوتشات دجاج", name: "رانشي مانشي", price: 130,
      description: "صدور دجاج فريش، صوص رانش، بصل مكرمل، تركي مدخن، مايونيز، مخلل، خس",
      mods: [{ group: CHICKEN_SIZE_GROUP, required: true, mods: [["سمول", 0], ["لارج", 20]] }] },
    { category: "سندوتشات دجاج", name: "تشيز لافرز", price: 130,
      description: "صدور دجاج فريش، موتزريلا ستيكس، مايونيز، صوص شيدر، مخلل، خس",
      mods: [{ group: CHICKEN_SIZE_GROUP, required: true, mods: [["سمول", 0], ["لارج", 20]] }] },
    { category: "سندوتشات دجاج", name: "تشيكن رن", price: 140,
      description: "صدور دجاج فريش، صوص كريمي، موتزريلا ستيكس، تركي مدخن، حلقات بصل، مخلل، خس",
      mods: [{ group: CHICKEN_SIZE_GROUP, required: true, mods: [["سمول", 0], ["لارج", 20]] }] },
    { category: "سندوتشات دجاج", name: "تشيكن راب", price: 110,
      description: "خبز تورتيلا، صدور دجاج فريش، صوص شيدر، تركي مدخن، مايونيز أو لافا سبايسي" },

    # — وجبات على السريع —
    { category: "وجبات على السريع", name: "تشيز فرايز", price: 55 },
    { category: "وجبات على السريع", name: "فاير فرايز", price: 60 },
    { category: "وجبات على السريع", name: "كرانشي فرايز", price: 80 },

    # — وجبات فردية —
    { category: "وجبات فردية", name: "سناك بوكس 2 قطع", price: 125,
      description: "2 قطع دجاج + بطاطس + 1 خبز + صوص + كاتشب" },
    { category: "وجبات فردية", name: "دينر بوكس 3 قطع", price: 190,
      description: "3 قطع دجاج + بطاطس + أرز + 2 خبز + صوص + كاتشب" },
    { category: "وجبات فردية", name: "سوبر دينر بوكس 4 قطع", price: 235,
      description: "4 قطع دجاج + بطاطس + أرز + 2 خبز + صوص + كاتشب" },
    { category: "وجبات فردية", name: "ميكس بوكس 4 قطع", price: 195,
      description: "2 قطع دجاج + 2 قطع استربس + بطاطس + أرز + 2 خبز + صوص + كاتشب" },
    { category: "وجبات فردية", name: "فاليو ميل 6 قطع", price: 345,
      description: "6 قطع دجاج + بطاطس + 3 خبز + صوص + كاتشب + كولسلو" },
    { category: "وجبات فردية", name: "وجبة صولو 3 قطع", price: 125,
      description: "3 قطع استربس + بطاطس + 2 خبز + صوص" },
    { category: "وجبات فردية", name: "توين تندر 5 قطع", price: 190,
      description: "5 قطع استربس + بطاطس + 3 خبز + كولسلو + صوص" },
    { category: "وجبات فردية", name: "تندر اكسترا 7 قطع", price: 235,
      description: "7 قطع استربس + بطاطس + 3 خبز + كولسلو + صوص" },
    { category: "وجبات فردية", name: "وجبة ريزو", price: 80,
      description: "2 قطعة استربس + أرز + صوص" },
    { category: "وجبات فردية", name: "وجبة ريزو جريل", price: 80,
      description: "2 قطعة دجاج جريل + أرز + صوص" },

    # — وجبات عائلية —
    { category: "وجبات عائلية", name: "فاميلي ميل 9 قطع", price: 520,
      description: "9 قطع دجاج + بطاطس + 4 خبز + كولسلو + صوص + كاتشب" },
    { category: "وجبات عائلية", name: "وجبة العيلة 12 قطعة", price: 690,
      description: "12 قطعة دجاج + بطاطس عائلي + 6 خبز + 2 كولسلو + 2 صوص + كاتشب + لتر كولا" },
    { category: "وجبات عائلية", name: "وجبة اقتصادية 15 قطعة", price: 830,
      description: "15 قطعة دجاج + بطاطس عائلي + 7 خبز + 2 كولسلو + 2 صوص + كاتشب + لتر كولا" },
    { category: "وجبات عائلية", name: "سوبر فاميلي ميل 18 قطعة", price: 920,
      description: "18 قطعة دجاج + بطاطس عائلي + 9 خبز + 3 كولسلو + 3 صوص + كاتشب + لتر كولا" },
    { category: "وجبات عائلية", name: "فرايتي ميل 12 قطعة", price: 550,
      description: "6 قطع دجاج + 6 قطع استربس + بطاطس عائلي + 6 خبز + 2 كولسلو + 2 صوص + كاتشب + لتر كولا" },
    { category: "وجبات عائلية", name: "فاميلي استربس 12 قطعة", price: 460,
      description: "12 قطعة استربس + بطاطس عائلي + 5 خبز + 1 كولسلو + 2 صوص + كولا" },

    # — وجبات الأطفال —
    { category: "وجبات الأطفال", name: "هابي ميل تشيكن", price: 100,
      description: "قطعة دجاج مع بطاطس وخبز وعصير" },
    { category: "وجبات الأطفال", name: "هابي ميل استربس", price: 100,
      description: "2 قطعة استربس مع بطاطس وخبز وعصير" },

    # — الإضافات —
    { category: "الإضافات", name: "فرايز (صغير)", price: 30 },
    { category: "الإضافات", name: "فرايز (كبير)", price: 45 },
    { category: "الإضافات", name: "أرز مبهر سادة", price: 25 },
    { category: "الإضافات", name: "كولسلو", price: 20 },
    { category: "الإضافات", name: "ثومية", price: 10 },
    { category: "الإضافات", name: "حلقات بصل", price: 35 },
    { category: "الإضافات", name: "موتزريلا", price: 45 },
    { category: "الإضافات", name: "صوص جبنة", price: 20 },
    { category: "الإضافات", name: "صوص رانش", price: 20 },
    { category: "الإضافات", name: "صوص باربيكيو", price: 10 },
    { category: "الإضافات", name: "صوص تكساس", price: 20 },
    { category: "الإضافات", name: "قطعة دجاج", price: 65 },
    { category: "الإضافات", name: "تبديل قطعة", price: 45 },
    { category: "الإضافات", name: "قطعة استربس", price: 40 },
    { category: "الإضافات", name: "2 عيش", price: 10 },
    { category: "الإضافات", name: "كولا (صغير)", price: 20, tax: "beverage" },
    { category: "الإضافات", name: "كولا (كبير)", price: 25, tax: "beverage" },
    { category: "الإضافات", name: "لتر كولا", price: 35, tax: "beverage" },
    { category: "الإضافات", name: "عصير", price: 20, tax: "beverage" },
    { category: "الإضافات", name: "مياه", price: 10, tax: "beverage" }
  ].freeze

  module_function

  def seed!(company:)
    deactivate_existing_menu!(company: company)

    categories = {}
    CATEGORIES.each do |attrs|
      categories[attrs[:name]] = Category.find_or_create_by!(name: attrs[:name], company: company) do |cat|
        cat.position = attrs[:position]
        cat.active = true
      end.tap { |cat| cat.update!(position: attrs[:position], active: true) }
    end

    modifier_group_cache = {}
    ITEMS.each_with_index do |data, index|
      category = categories.fetch(data[:category])
      tax = data[:tax] || "food"

      item = MenuItem.find_or_initialize_by(name: data[:name], company: company)
      item.assign_attributes(
        category: category,
        description: data[:description],
        base_price_cents: data[:price] * 100,
        tax_category: tax,
        available: true,
        position: index
      )
      item.save!

      Array(data[:mods]).each_with_index do |mg_data, mg_index|
        group_name = mg_data[:group]
        group = modifier_group_cache[group_name] ||= begin
          g = ModifierGroup.find_or_create_by!(name: group_name) do |gr|
            gr.required = mg_data[:required] || false
            gr.multi_select = false
          end
          g.update!(required: true) if mg_data[:required] && !g.required?
          mg_data[:mods].each_with_index do |(mod_name, price_egp), mod_index|
            g.modifiers.find_or_create_by!(name: mod_name) do |mod|
              mod.price_adjustment_cents = price_egp * 100
              mod.position = mod_index
            end
          end
          g
        end

        MenuItemModifierGroup.find_or_create_by!(menu_item: item, modifier_group: group) do |join|
          join.position = mg_index
        end
      end
    end
  end

  def deactivate_existing_menu!(company:)
    catalog_names = ITEMS.map { |data| data[:name] }.to_set

    MenuItem.where(company: company).where.not(name: catalog_names).update_all(available: false)
    LocationMenuItem.joins(:menu_item)
      .where(menu_items: { company_id: company.id })
      .where.not(menu_items: { name: catalog_names.to_a })
      .update_all(available: false)
    Combo.where(company: company).update_all(active: false)
    Category.where(company: company).where.not(name: CATEGORIES.map { |c| c[:name] }).update_all(active: false)
  end

  def seed_location_menu!(location:)
    MenuItem.where(company: location.company, available: true).find_each do |item|
      lmi = LocationMenuItem.find_or_initialize_by(location: location, menu_item: item)
      lmi.available = true
      lmi.save!
    end
  end
end
