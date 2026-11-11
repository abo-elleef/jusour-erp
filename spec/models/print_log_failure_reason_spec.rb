# frozen_string_literal: true

require "rails_helper"

RSpec.describe PrintLog, "#failure_reason_key" do
  def key_for(message, printer_id: SecureRandom.uuid)
    PrintLog.new(error_message: message, printer_id: printer_id).failure_reason_key
  end

  it "reads the errors seen in production" do
    expect(key_for("Failed to fetch")).to eq(:agent_unreachable)
    expect(key_for("Connection timed out after 5000ms")).to eq(:printer_timeout)
    expect(key_for("connect ECONNREFUSED 192.168.1.210:9100")).to eq(:printer_refused)
    expect(key_for("connect EHOSTUNREACH 192.168.1.210:9100")).to eq(:printer_unreachable)
    expect(key_for("usb_printer_missing_device_name")).to eq(:usb_device_missing)
    expect(key_for("no_active_receipt_printer")).to eq(:no_printer)
  end

  it "falls back to no printer, then unknown" do
    expect(key_for(nil, printer_id: nil)).to eq(:no_printer)
    expect(key_for("something odd")).to eq(:unknown)
  end

  it "has a reason and a checklist for every key, in both languages" do
    keys = %i[agent_unreachable printer_timeout printer_refused printer_unreachable usb_device_missing no_printer unknown]
    %i[en ar].each do |locale|
      keys.each do |k|
        expect(I18n.t("printing.status.reasons.#{k}", locale: locale, raise: true)).to be_present
        expect(I18n.t("printing.status.checks.#{k}", locale: locale, raise: true)).to be_an(Array)
      end
    end
  end
end
