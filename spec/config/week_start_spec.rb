# frozen_string_literal: true

require "rails_helper"

# The business week runs Saturday to Friday. The weekend here is Friday and
# Saturday, so Rails' default Monday start splits every weekend across two
# weeks — payroll hours, overtime and weekly reports all land in the wrong
# bucket. Set once in config/application.rb; everything that asks for a week
# inherits it.
RSpec.describe "Week boundary", type: :model do
  it "starts the week on Saturday, app-wide" do
    expect(Date.beginning_of_week).to eq(:saturday)
  end

  it "runs a week Saturday through Friday" do
    midweek = Date.new(2026, 9, 3) # a Thursday

    expect(midweek.beginning_of_week.strftime("%A")).to eq("Saturday")
    expect(midweek.end_of_week.strftime("%A")).to eq("Friday")
    expect(midweek.beginning_of_week).to eq(Date.new(2026, 8, 29))
    expect(midweek.end_of_week).to eq(Date.new(2026, 9, 4))
  end

  it "applies to Time and ActiveSupport::TimeWithZone too, not just Date" do
    moment = Time.zone.local(2026, 9, 3, 14, 30)

    expect(moment.beginning_of_week.strftime("%A")).to eq("Saturday")
    expect(moment.end_of_week.strftime("%A")).to eq("Friday")
  end

  # A Friday and the Saturday after it are consecutive days but different weeks;
  # a Friday and the Saturday before it share a week. This is exactly the case a
  # Monday-start week gets wrong.
  it "keeps a Friday and Saturday weekend inside one week" do
    friday = Date.new(2026, 9, 4)
    saturday_before = Date.new(2026, 8, 29)
    saturday_after = Date.new(2026, 9, 5)

    expect(friday.beginning_of_week).to eq(saturday_before)
    expect(saturday_after.beginning_of_week).to eq(saturday_after)
    expect(saturday_after.beginning_of_week).not_to eq(friday.beginning_of_week)
  end
end
