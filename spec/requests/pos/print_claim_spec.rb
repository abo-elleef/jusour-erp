# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Print jobs shared by every register at a branch", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:order) { create(:order, user: cashier, company: company, location: branch, status: "submitted") }
  let!(:printer) do
    Printer.create!(company: company, location: branch, name: "Grill", printer_type: "kitchen", station: "Grill",
                    connection_type: "network", host: "192.168.1.60", port: 9100, paper_width: "80mm", active: true)
  end
  let!(:log) { PrintLog.create!(order: order, printer: printer, print_type: "kitchen", status: "pending") }

  before do
    Current.company = company
    create(:order_item, order: order)
    sign_in cashier
  end

  it "hands the payload to the first register and tells the second to stand down" do
    get payload_pos_print_log_path(log, client_id: "register-a")
    expect(response).to have_http_status(:ok)

    get payload_pos_print_log_path(log, client_id: "register-b")
    expect(response).to have_http_status(:conflict)
  end

  it "lets the same register fetch again after a hiccup" do
    2.times do
      get payload_pos_print_log_path(log, client_id: "register-a")
      expect(response).to have_http_status(:ok)
    end
  end

  it "does not offer a job another register is printing when a page recovers pending work" do
    get payload_pos_print_log_path(log, client_id: "register-a")

    get pending_pos_print_logs_path
    expect(JSON.parse(response.body).map { |j| j["id"] }).not_to include(log.id)
  end

  it "still offers an unclaimed pending job on recovery" do
    get pending_pos_print_logs_path
    expect(JSON.parse(response.body).map { |j| j["id"] }).to include(log.id)
  end

  it "does not let a late 'failed' overwrite a job that was already sent" do
    patch confirm_pos_print_log_path(log), params: { status: "sent" }, as: :json
    patch confirm_pos_print_log_path(log), params: { status: "failed", error_message: "late" }, as: :json

    expect(log.reload.status).to eq("sent")
  end
end

RSpec.describe Printing::PrintOrderService, "repeated requests" do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:branch) { create(:location, company: company) }
  let(:order) { create(:order, user: user, company: company, location: branch, status: "submitted") }
  let!(:printer) do
    Printer.create!(company: company, location: branch, name: "Kitchen", printer_type: "kitchen",
                    connection_type: "network", host: "192.168.1.51", port: 9100, paper_width: "80mm",
                    active: true, is_default: true)
  end

  before do
    Current.company = company
    Setting.set("print_routing", Printing::Config::ROUTING_CLIENT)
    create(:order_item, order: order)
  end

  it "queues one job for a ticket asked for twice in a row, but a later reprint still goes out" do
    expect { 2.times { described_class.call(order: order, print_type: "kitchen") } }
      .to change(PrintLog, :count).by(1)

    PrintLog.update_all(created_at: 10.seconds.ago)
    expect { described_class.call(order: order, print_type: "kitchen") }.to change(PrintLog, :count).by(1)
  end
end
