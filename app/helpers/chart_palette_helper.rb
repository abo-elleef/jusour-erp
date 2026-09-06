# frozen_string_literal: true

# Chartkick ships 20 colours and indexes them directly (`colors[i]`, no wrap), so
# a chart with more series than that hands Chart.js `undefined` and every line
# past the 20th is painted the same default grey. A report that routinely carries
# 80+ ingredients needs a palette as long as its data.
module ChartPaletteHelper
  # Successive hues land ~137.5° apart, which spreads any number of colours
  # evenly around the wheel without ever repeating. It also means neighbours in
  # the list get very different hues — the case that matters, since selections
  # are usually a contiguous slice ("Top 8", or whatever a search turned up).
  GOLDEN_ANGLE = 137.507764050038

  # Saturation/lightness pairs cycled alongside the hue, so two colours that do
  # land near each other still differ in weight. All are dark enough to read as
  # a thin line on white.
  BANDS = [[0.68, 0.45], [0.85, 0.34], [0.55, 0.56]].freeze

  def chart_series_colors(count)
    Array.new(count) do |index|
      saturation, lightness = BANDS[index % BANDS.size]
      hsl_hex((index * GOLDEN_ANGLE) % 360, saturation, lightness)
    end
  end

  private

  def hsl_hex(hue, saturation, lightness)
    chroma = (1 - ((2 * lightness) - 1).abs) * saturation
    second = chroma * (1 - (((hue / 60.0) % 2) - 1).abs)
    match = lightness - (chroma / 2.0)

    red, green, blue =
      case hue
      when 0...60    then [chroma, second, 0]
      when 60...120  then [second, chroma, 0]
      when 120...180 then [0, chroma, second]
      when 180...240 then [0, second, chroma]
      when 240...300 then [second, 0, chroma]
      else                [chroma, 0, second]
      end

    format("#%02X%02X%02X", *[red, green, blue].map { |value| (((value + match) * 255).round).clamp(0, 255) })
  end
end
