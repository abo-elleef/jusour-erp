# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChartPaletteHelper, type: :helper do
  def luminance(hex)
    red, green, blue = hex[1, 6].scan(/../).map { |pair| pair.to_i(16) }
    (0.299 * red) + (0.587 * green) + (0.114 * blue)
  end

  it "returns exactly as many colours as asked for" do
    expect(helper.chart_series_colors(0)).to eq([])
    expect(helper.chart_series_colors(1).size).to eq(1)
    expect(helper.chart_series_colors(84).size).to eq(84)
  end

  # The bug this exists to prevent: chartkick's own list stops at 20 and hands
  # Chart.js nil past that, which it paints grey.
  it "keeps every colour distinct well past chartkick's 20" do
    colors = helper.chart_series_colors(120)

    expect(colors.uniq.size).to eq(120)
    expect(colors).to all(match(/\A#[0-9A-F]{6}\z/))
  end

  it "never emits a colour too pale to read as a line on white" do
    expect(helper.chart_series_colors(120).map { |hex| luminance(hex) }.max).to be < 210
  end

  it "gives neighbouring series clearly different hues" do
    # Selections are usually a contiguous slice, so adjacent entries are the ones
    # most likely to be on screen together.
    colors = helper.chart_series_colors(30)

    colors.each_cons(2) do |first, second|
      difference = first[1, 6].scan(/../).zip(second[1, 6].scan(/../))
        .sum { |a, b| (a.to_i(16) - b.to_i(16)).abs }
      expect(difference).to be > 60
    end
  end

  it "is stable, so a series keeps its colour between page loads" do
    expect(helper.chart_series_colors(40)).to eq(helper.chart_series_colors(40))
    expect(helper.chart_series_colors(40).first(10)).to eq(helper.chart_series_colors(10))
  end
end
