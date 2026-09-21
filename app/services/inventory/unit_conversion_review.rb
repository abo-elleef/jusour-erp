# frozen_string_literal: true

module Inventory
  # Puts every ingredient's alternate-unit factors side by side so a wrong
  # "1 carton = N base units" is visible without opening 250 ingredient pages.
  #
  # On top of listing them, each row gets an *expected* factor wherever the data
  # can supply one, and the reason it is expected:
  #
  #   :physical  both units are real measures — 1 kg is 1000 g, always
  #   :pack      the unit names carry their own count ("carton * 12", "10kg sack")
  #   :peer      other ingredients already convert this same pair differently
  #
  # These are hints for a human reviewing the list, never a verdict: a factor
  # flagged for check may well be right (a supplier's "column" really does hold
  # 20 cups). Nothing here changes data — the page offers the correction, the
  # admin decides.
  class UnitConversionReview
    # A factor derived from arithmetic on the units themselves should match to
    # the last stored decimal; one read out of a unit's *name* is softer — names
    # round ("1/60 of a 60kg drum" entered as 0.017), so allow a little drift.
    EXACT_TOLERANCE = 0.01
    NAME_TOLERANCE  = 0.03

    # Mass in grams, volume in millilitres. Only used to compare two units of
    # the same dimension against each other, so the common scale is arbitrary.
    MASS = {
      "kg" => 1000.0, "g" => 1.0, "lbs" => 453.59237, "oz" => 28.349523125
    }.freeze
    VOLUME = {
      "liters" => 1000.0, "ml" => 1.0, "gallons" => 3785.411784
    }.freeze

    # Words that name a measure, in the languages the unit list is actually
    # written in. Longest first so "kilogram" wins over "gram" at the same spot.
    WORDS = [
      ["kg",      %w[kilogram kilograms kilo kgs kg كيلوجرام كيلوجرم كيلو كجم]],
      ["g",       %w[grams gram جرامات جرام جم gm gr g]],
      ["liters",  %w[liters litres liter litre لتر لترات ltr l]],
      ["ml",      %w[ml مللي ملي مل]],
      ["lbs",     %w[pounds pound lbs lb رطل]],
      ["oz",      %w[ounces ounce oz اونز أونز]],
      ["gallons", %w[gallons gallon جالون جالونات]]
    ].freeze

    # A name that says "half" or "quarter" states a size no digit captures, so
    # its measure word ("½ kilo bag") must not be read as a plain 1 kg.
    FRACTION_WORDS = %w[half quarter نص نصف ربع].freeze

    Row = Struct.new(
      :ingredient_unit, :ingredient, :base_unit, :alt_unit, :factor,
      :expected, :basis, :peer_count, :status,
      keyword_init: true
    ) do
      def check?      = status == :check
      def verified?   = status == :ok
      def unverified? = status == :unverified
      def id          = ingredient_unit.id
    end

    # `rows` are the conversions to report on (already filtered for display);
    # `peers` is every conversion in the company, so the "other ingredients use
    # X for this pair" check keeps working on a filtered page.
    def initialize(rows, peers: nil)
      @rows  = rows.to_a
      @peers = (peers || @rows).to_a
    end

    def rows
      @built ||= @rows.map { |iu| build_row(iu) }
    end

    def checks
      rows.select(&:check?)
    end

    private

    def build_row(ingredient_unit)
      ingredient = ingredient_unit.ingredient
      base       = ingredient.unit.to_s
      alt        = ingredient_unit.unit.to_s
      factor     = ingredient_unit.base_units_per_unit.to_d

      expected, basis = expectation(base, alt, factor, ingredient_unit)
      peer_count = (basis == :peer ? peer_tally(ingredient_unit)[1] : nil)
      status = classify(factor, expected, basis)

      # An alternate unit the same size as the base converts nothing — almost
      # always a row someone added and never filled in. Whatever else the data
      # says about it, that is the thing to report.
      basis = :identity if factor == 1

      Row.new(
        ingredient_unit: ingredient_unit, ingredient: ingredient,
        base_unit: base, alt_unit: alt, factor: factor,
        expected: expected, basis: basis, peer_count: peer_count, status: status
      )
    end

    # The strongest available expectation wins: arithmetic on the units beats a
    # reading of their names, and both beat "everyone else does it differently".
    def expectation(base, alt, factor, ingredient_unit)
      from_pack = pack_expectation(base, alt)
      return [from_pack, :pack] if from_pack

      from_physical, exact = physical_expectation(base, alt)
      return [from_physical, exact ? :physical : :pack] if from_physical

      from_name = name_size_expectation(base, alt)
      return [from_name, :pack] if from_name

      peer, count = peer_tally(ingredient_unit)
      return [peer, :peer] if peer && count >= 2 && !within?(factor, peer, EXACT_TOLERANCE)

      [nil, nil]
    end

    # "carton * 12" over "carton * 1000" is 12/1000; over a base that carries no
    # count of its own, a "* 12" simply means twelve of it.
    def pack_expectation(base, alt)
      alt_pack  = pack_count(alt)
      return nil if alt_pack.nil?

      base_pack = pack_count(base)
      base_pack ? alt_pack / base_pack : alt_pack
    end

    # Returns [factor, exact] — exact only when both names *are* measures
    # ("kg" vs "g"). A size read out of a name ("60kg drum") is rounder than the
    # arithmetic suggests, so it is compared with the looser tolerance.
    def physical_expectation(base, alt)
      base_size = physical_size(base)
      alt_size  = physical_size(alt)
      return nil if base_size.nil? || alt_size.nil?
      return nil if base_size[:dimension] != alt_size[:dimension]

      [(alt_size[:amount] / base_size[:amount]).to_d, base_size[:exact] && alt_size[:exact]]
    end

    # A name can spell out its size in the *other* unit: a "chicken bag (14
    # pieces)" against a base of pieces is 14; read the other way, a base of
    # "strips bag (20 pieces)" against pieces is one twentieth.
    def name_size_expectation(base, alt)
      count = counted_in(alt, base)
      return count if count

      count = counted_in(base, alt)
      return nil if count.nil? || count.zero?

      (1.to_d / count)
    end

    # Looks for "<number> <word>" inside `name`, where the word names `unit`.
    def counted_in(name, unit)
      normalized = normalize(name)
      unit_tokens(unit).each do |token|
        match = normalized.match(/(\d+(?:[.,]\d+)?)\s*#{Regexp.escape(token)}/)
        return to_decimal(match[1]) if match
      end
      nil
    end

    # Significant words of a unit's name — what to look for inside another name.
    def unit_tokens(unit)
      normalize(unit).split(/[\s*×x()]+/).reject { |t| t.length < 2 || t.match?(/\A[\d.,]+\z/) }
    end

    # The "* 12" / "×12" / "x 50" a packaging unit is named after.
    def pack_count(name)
      match = normalize(name).match(/[*×]\s*(\d+(?:[.,]\d+)?)/)
      return nil unless match

      count = to_decimal(match[1])
      count&.positive? ? count : nil
    end

    # Resolves a unit name to a real measure: either it *is* one ("kg"), or it
    # states one ("10 kilo sack", "430g net tin"). Returns nil when the name is
    # a bare container ("carton", "bottle 2200") with nothing to measure it by.
    def physical_size(name)
      normalized = normalize(name)
      return nil if FRACTION_WORDS.any? { |w| normalized.include?(w) }

      numbered = numbered_measure(normalized)
      return numbered.merge(exact: false) if numbered

      bare = bare_measure(normalized)
      return nil if bare.nil?

      { dimension: bare[:dimension], amount: bare[:scale], exact: true }
    end

    # "10 كيلو" / "430 جرام" — a measure word with a quantity in front of it.
    def numbered_measure(normalized)
      best = nil
      each_measure_word(normalized) do |word, index, unit|
        prefix = normalized[0...index]
        quantity = prefix[/(\d+(?:[.,]\d+)?)\s*\z/, 1]
        next if quantity.blank?

        amount = to_decimal(quantity)
        next if amount.nil? || !amount.positive?

        best ||= { dimension: dimension_of(unit), amount: amount * scale_of(unit), word: word }
      end
      best
    end

    # A name that is itself a measure ("kg", "كيلو جرام") — one unit of it.
    def bare_measure(normalized)
      found = nil
      each_measure_word(normalized) do |_word, _index, unit|
        found ||= { dimension: dimension_of(unit), scale: scale_of(unit) }
      end
      found
    end

    # Yields every measure word in the name, earliest first, longest match at a
    # given position (so "كيلو جرام" reads as kilograms, not grams).
    def each_measure_word(normalized)
      hits = []
      WORDS.each do |unit, words|
        words.each do |word|
          index = word_index(normalized, word)
          hits << [word, index, unit] if index
        end
      end
      hits.sort_by { |word, index, _unit| [index, -word.length] }
        .each { |word, index, unit| yield(word, index, unit) }
    end

    # Matches a word on its own, not as a fragment of a longer Latin word
    # ("l" must not fire inside "lux"). Arabic has no case and clitics attach
    # freely, so non-Latin words match anywhere.
    def word_index(normalized, word)
      if word.match?(/\A[a-z]+\z/)
        normalized.index(/(?<![a-z])#{Regexp.escape(word)}(?![a-z])/)
      else
        normalized.index(word)
      end
    end

    def dimension_of(unit)
      MASS.key?(unit) ? :mass : :volume
    end

    def scale_of(unit)
      MASS[unit] || VOLUME[unit]
    end

    # The factor other ingredients agree on for this same pair of units, with
    # how many of them say so.
    def peer_tally(ingredient_unit)
      @peer_tallies ||= @peers.group_by { |iu| [iu.ingredient&.unit_id, iu.unit_id] }
        .transform_values do |group|
          counts = group.group_by { |iu| iu.base_units_per_unit.to_d }.transform_values(&:size)
          counts.max_by { |factor, count| [count, factor] }
        end

      tally = @peer_tallies[[ingredient_unit.ingredient&.unit_id, ingredient_unit.unit_id]]
      return [nil, 0] if tally.nil?

      mode, count = tally
      # Don't let a row vouch for itself: the agreement has to come from others.
      count -= 1 if within?(ingredient_unit.base_units_per_unit.to_d, mode, EXACT_TOLERANCE)
      [mode, count]
    end

    def classify(factor, expected, basis)
      return :check if factor == 1
      return :unverified if expected.nil?

      tolerance = basis == :physical ? EXACT_TOLERANCE : NAME_TOLERANCE
      within?(factor, expected, tolerance) ? :ok : :check
    end

    def within?(actual, expected, tolerance)
      return false if expected.nil? || expected.zero?

      ((actual - expected).abs / expected.abs) <= tolerance
    end

    ARABIC_DIGITS = ("٠".."٩").zip("0".."9").to_h.merge(("۰".."۹").zip("0".."9").to_h).freeze

    def normalize(name)
      name.to_s.downcase.tr(ARABIC_DIGITS.keys.join, ARABIC_DIGITS.values.join).squeeze(" ").strip
    end

    def to_decimal(string)
      BigDecimal(string.to_s.tr(",", "."))
    rescue ArgumentError, TypeError
      nil
    end
  end
end
