# frozen_string_literal: true

require "rails_helper"

RSpec.describe Location, "online ordering" do
  let(:company) { create(:company, timezone: "Africa/Cairo") }
  let(:branch) do
    create(:location, company: company, public_menu_enabled: true, online_ordering_enabled: true)
  end
  let(:zone) { ActiveSupport::TimeZone["Africa/Cairo"] }

  before { Current.company = company }

  def at(hh_mm)
    zone.parse("2026-11-14 #{hh_mm}")
  end

  describe "#accepting_online_orders?" do
    it "is open any time when no hours are set" do
      expect(branch.accepting_online_orders?(at("03:00"))).to be(true)
      expect(branch.accepting_online_orders?(at("15:00"))).to be(true)
    end

    it "is closed when online ordering is off" do
      branch.update!(online_ordering_enabled: false)
      expect(branch.accepting_online_orders?(at("15:00"))).to be(false)
    end

    it "is closed when the public menu is off or the branch is inactive" do
      branch.update!(public_menu_enabled: false)
      expect(branch.accepting_online_orders?).to be(false)

      branch.update!(public_menu_enabled: true, active: false)
      expect(branch.accepting_online_orders?).to be(false)
    end

    it "opens at the open time and closes at the close time, same day" do
      branch.update!(online_open_time: "10:00", online_close_time: "22:00")
      expect(branch.accepting_online_orders?(at("09:59"))).to be(false)
      expect(branch.accepting_online_orders?(at("10:00"))).to be(true)
      expect(branch.accepting_online_orders?(at("21:59"))).to be(true)
      expect(branch.accepting_online_orders?(at("22:00"))).to be(false)
    end

    it "handles a window that runs past midnight" do
      branch.update!(online_open_time: "18:00", online_close_time: "02:00")
      expect(branch.accepting_online_orders?(at("17:59"))).to be(false)
      expect(branch.accepting_online_orders?(at("23:00"))).to be(true)
      expect(branch.accepting_online_orders?(at("01:30"))).to be(true)
      expect(branch.accepting_online_orders?(at("02:00"))).to be(false)
      expect(branch.accepting_online_orders?(at("12:00"))).to be(false)
    end

    it "reads the hours in the company's timezone, not the server's" do
      branch.update!(online_open_time: "10:00", online_close_time: "22:00")
      # 21:30 in Cairo is 19:30 UTC; 22:30 in Cairo is 20:30 UTC.
      expect(branch.accepting_online_orders?(Time.utc(2026, 11, 14, 19, 30))).to be(true)
      expect(branch.accepting_online_orders?(Time.utc(2026, 11, 14, 20, 30))).to be(false)
    end

    it "keeps the hours as typed whatever Time.zone is when they are read" do
      branch.update!(online_open_time: "10:00", online_close_time: "22:00")
      Time.use_zone("UTC") do
        expect(Location.find(branch.id).online_open_time.strftime("%H:%M")).to eq("10:00")
      end
    end
  end

  describe "validations" do
    it "needs both hours or neither" do
      branch.online_open_time = "10:00"
      expect(branch).not_to be_valid
      branch.online_close_time = "22:00"
      expect(branch).to be_valid
    end

    it "keeps the accept timeout between 1 and 120 minutes" do
      expect(branch.online_accept_timeout_minutes).to eq(10)
      branch.online_accept_timeout_minutes = 0
      expect(branch).not_to be_valid
      branch.online_accept_timeout_minutes = 121
      expect(branch).not_to be_valid
    end

    it "defaults a blank accept timeout back to 10" do
      branch.update!(online_accept_timeout_minutes: "")
      expect(branch.online_accept_timeout_minutes).to eq(10)
    end

    it "reads the order cap in pounds, blank meaning no cap" do
      branch.update!(online_max_order_pounds: "500")
      expect(branch.online_max_order_cents).to eq(50_000)
      branch.update!(online_max_order_pounds: "")
      expect(branch.online_max_order_cents).to be_nil
    end

    it "turns online ordering off for a central kitchen" do
      kitchen = create(:location, :central_kitchen, company: company, online_ordering_enabled: true)
      expect(kitchen.online_ordering_enabled).to be(false)
    end
  end
end
