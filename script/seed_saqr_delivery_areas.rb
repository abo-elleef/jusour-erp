# frozen_string_literal: true

# One-off: load SAQR's delivery areas and fees (from the price sheet, 2026-11-16; duplicates resolved by the user).
#
# Run on production:
#   heroku run rails console -a rest-management-system
#   load "script/seed_saqr_delivery_areas.rb"
#
# Safe to re-run: areas are matched by English name per branch, so a second run
# updates fees / Arabic names instead of creating duplicates. Every area is set
# active (open for delivery).
#
# It is a dry run by default (prints what it would do, then rolls back). To save:
#   $apply = true
#   load "script/seed_saqr_delivery_areas.rb"
# The file can also be pasted straight into the console instead of loaded.

DRY_RUN = ($apply != true)
COMPANY_SLUG  = "saqr"   # exact companies.slug
BRANCH_NAME   = "المطعم" # the branch that delivers (SAQR also has الكافيه and الكشك)

# [English name, Arabic name, fee in EGP]
AREAS = [
  ["El Salam Tanbul El Gedida",   "السلام طنبول الجديده",        100],
  ["Kafr Azzam",                  "كفر عزام",                    100],
  ["Shubrahur",                   "شبراهور",                     100],
  ["Nub",                         "نوب",                         60],
  ["Shubra Qabala",               "شبرا قباله",                  60],
  ["El Galayla",                  "الجلايله",                    90],
  ["Beshmes",                     "بشمس",                        60],
  ["Tmai",                        "تمي",                         150],
  ["Mit Ghareeta",                "ميت غريطه",                   90],
  ["El Hasayna",                  "الحصاينه",                    70],
  ["Abu Qarameet",                "ابو قراميط",                  70],
  ["El Zureiqi",                  "الزريقي",                     90],
  ["Tanbara",                     "طنباره",                      70],
  ["Dawy El Wosta",               "دوي الوسطي",                  70],
  ["Taranis",                     "طرانيس",                      60],
  ["Temed",                       "تمد",                         150],
  ["Barqeen",                     "برقين",                       80],
  ["Kafr El Rouk",                "كفر الروك",                   100],
  ["Kafr Qansuh",                 "كفر قنصوه",                   90],
  ["El Zahayra",                  "الزهايره",                    70],
  ["Tamay",                       "طماي",                        60],
  ["Shubra Sendi",                "شبرا سندي",                   100],
  ["Abu Dawood",                  "ابو داود",                    160],
  ["El Ezab",                     "العزب",                       60],
  ["El Balamoun",                 "البلامون",                    110],
  ["Kafr El Amir",                "كفر الامير",                  150],
  ["El Moqataa",                  "المقاطعه",                    160],
  ["Menshiet Gebran",             "منشيه جبران",                 60],
  ["Kafr Abdel Amin",             "كفر عبد الامين",              160],
  ["El Orman",                    "الاورمان",                    100],
  ["El Makhzan",                  "المخزن",                      100],
  ["Kafr Badawy",                 "كفر بدوي",                    50],
  ["Tukh",                        "طوخ",                         60],
  ["Mit Ghorab",                  "ميت غراب",                    100],
  ["Tahway",                      "طهواي",                       150],
  ["Ezbet El Rawda",              "عزبه الروضه",                 80],
  ["El Sharafa",                  "الشرفه",                      80],
  ["Borg El Nour",                "برج النور",                   80],
  ["El Baqliya",                  "البقليه",                     90],
  ["El Hamra",                    "الحمرا",                      45],
  ["El Rabawat",                  "الربوات",                     70],
  ["Tanbul El Kebira (Old)",      "طنبول الكبيره - القديمه",     120],
  ["Barhamtoush",                 "برهمتوش",                     160],
  ["El Rawda",                    "الروضه",                      80],
  ["Ezbet El Banzina",            "عزبه البنزينه",               100],
  ["El Bakkariya (not served after 7)", "البكاريه / غير مخدومه بعد 7", 100],
  ["El Ramziya",                  "الرمزيه",                     120],
  ["El Hegayza",                  "الحجايزه",                    160],
  ["El Matwa",                    "المتوه",                      130],
  ["Kafr Youssef",                "كفر يوسف",                    100],
  ["Abu Shalouba",                "ابو شلوبه",                   100],
  ["El Qasimi",                   "القاسمي",                     90],
  ["Ghazala",                     "غزاله",                       180],
  ["El Beshnini",                 "البشنيني",                    120],
  ["El Shoala",                   "الشعله",                      110],
  ["Menshaat El Reda",            "منشأة الرضا",                 100],
  ["Kafr El Shennawy",            "كفر الشناوى",                 50],
  ["El Markaz El Gedid",          "المركز الجديد",               30],
  ["Ezbet Ibrahim Abdel Galil",   "عزبه ابراهيم عبدالجليل",      50],
  # UNCLEAR on the sheet: a row named only "ت" at 120 — fill in the real name
  # ["???",                       "ت",                           120],
  ["Ezbet Abu Laban",             "عزبه ابولبن",                 50],
  ["Ezbet Ghazal",                "عزبه غزال",                   150],
  ["Qarqira",                     "قرقيره",                      130],
  ["Abu Shuquq",                  "ابو شقوق",                    160],
  ["Ezbet Rashad",                "عزبة رشاد",                   80],
  ["Mit El Amel",                 "ميت العامل",                  200],
].freeze

company = Company.find_by!(slug: COMPANY_SLUG)
Current.company = company

branches = Location.unscoped.where(company_id: company.id).branches.to_a
branch =
  if BRANCH_NAME
    branches.find { |b| b.name.casecmp?(BRANCH_NAME) } || raise("No branch #{BRANCH_NAME.inspect}; branches: #{branches.map(&:name).inspect}")
  elsif branches.size == 1
    branches.first
  else
    raise "#{company.name} has several branches — set BRANCH_NAME to one of: #{branches.map(&:name).inspect}"
  end

dupes = AREAS.map(&:first).group_by(&:downcase).select { |_, v| v.size > 1 }.keys
raise "Duplicate English names in AREAS: #{dupes.inspect}" if dupes.any?

puts "Company: #{company.name} | Branch: #{branch.name} | Areas: #{AREAS.size} | DRY_RUN=#{DRY_RUN}"
counts = Hash.new(0)

ActiveRecord::Base.transaction do
  start_position = branch.delivery_areas.maximum(:position).to_i

  AREAS.each_with_index do |(name, name_ar, fee), i|
    area = branch.delivery_areas.where("LOWER(name) = ?", name.downcase).first ||
           branch.delivery_areas.new(name: name, position: start_position + i + 1)
    action = area.new_record? ? :created : :updated
    area.assign_attributes(company: company, name_ar: name_ar, fee_cents: fee * 100, active: true)
    action = :unchanged if action == :updated && !area.changed?
    area.save!
    counts[action] += 1
    puts format("%-9s %-36s %-30s %5d EGP", action, name, name_ar, fee)
  end

  puts "\n#{counts.inspect}"
  puts "Active areas on #{branch.name} now: #{branch.delivery_areas.active.count}"

  if DRY_RUN
    puts "DRY RUN — rolling back. Set $apply = true and run again to save."
    raise ActiveRecord::Rollback
  end
end
