# frozen_string_literal: true

require "rails_helper"

# A register must be able to find every job it owes the printer, and a cashier must
# be able to see and retry what failed.
RSpec.describe "Print recovery and retry", type: :request do
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

  def ids = JSON.parse(response.body).map { |j| j["id"] }

  describe "pending" do
    it "hands a job back to the register that holds it (reloaded mid-print)" do
      get payload_pos_print_log_path(log, client_id: "register-a")

      get pending_pos_print_logs_path(client_id: "register-a")
      expect(ids).to include(log.id)
    end

    it "keeps it hidden from other registers while the claim is fresh" do
      get payload_pos_print_log_path(log, client_id: "register-a")

      get pending_pos_print_logs_path(client_id: "register-b")
      expect(ids).not_to include(log.id)
    end

    it "offers a retried job even when it was first created long ago" do
      log.update_columns(status: "failed", created_at: 5.hours.ago, updated_at: 5.hours.ago)
      log.requeue!

      get pending_pos_print_logs_path(client_id: "register-b")
      expect(ids).to include(log.id)
    end
  end

  describe "failed" do
    before { log.update!(status: "failed", error_message: "Failed to fetch") }

    it "lists failures that still need attention" do
      get failed_pos_print_logs_path
      body = JSON.parse(response.body)
      expect(body["count"]).to eq(1)
      group = body["groups"].first
      expect(group).to include("reason_key" => "agent_unreachable", "production" => true)
      expect(group["jobs"].first).to include("id" => log.id, "error" => "Failed to fetch", "printer" => "Grill",
                                             "order_number" => order.order_number)
    end

    it "groups failures by printer and cause, kitchen first" do
      receipt_printer = Printer.create!(company: company, location: branch, name: "Front", printer_type: "receipt",
                                        connection_type: "network", host: "192.168.1.61", port: 9100,
                                        paper_width: "80mm", active: true)
      other = create(:order, user: cashier, company: company, location: branch, status: "submitted")
      PrintLog.create!(order: other, printer: printer, print_type: "station", status: "failed",
                       error_message: "Failed to fetch")
      PrintLog.create!(order: other, printer: receipt_printer, print_type: "receipt", status: "failed",
                       error_message: "Connection timed out after 5000ms")
      PrintLog.create!(order: other, printer: printer, print_type: "station", status: "failed",
                       error_message: "Connection timed out after 5000ms")

      get failed_pos_print_logs_path
      groups = JSON.parse(response.body)["groups"]

      # Kitchen problems first (newest first), the receipt printer last. A dead print
      # agent is one card whatever printer it was printing to.
      agent_label = I18n.t("printing.status.agent_group")
      expect(groups.map { |g| [g["printer"], g["reason_key"], g["jobs"].size] }).to eq(
        [["Grill", "printer_timeout", 1], [agent_label, "agent_unreachable", 2], ["Front", "printer_timeout", 1]]
      )
      expect(groups.first["host"]).to eq("192.168.1.60:9100")
      agent_group = groups.find { |g| g["reason_key"] == "agent_unreachable" }
      expect(agent_group["checks"]).not_to be_empty
      expect(agent_group["report"]).to include("Grill", "192.168.1.60", "##{order.order_number}", "Failed to fetch")
    end

    it "drops a failure once the same ticket has since been printed" do
      PrintLog.create!(order: order, printer: printer, print_type: "kitchen", status: "sent")

      get failed_pos_print_logs_path
      expect(JSON.parse(response.body)["count"]).to eq(0)
    end

    it "ignores failures older than the window" do
      log.update_columns(updated_at: 13.hours.ago)

      get failed_pos_print_logs_path
      expect(JSON.parse(response.body)["count"]).to eq(0)
    end
  end

  describe "handle (printed by hand)" do
    it "clears a failed ticket without queuing it again" do
      log.update!(status: "failed", error_message: "Failed to fetch")
      expect(Turbo::StreamsChannel).not_to receive(:broadcast_append_to)

      post handle_pos_print_log_path(log), as: :json

      expect(response).to have_http_status(:ok)
      expect(log.reload.status).to eq("handled")
      get failed_pos_print_logs_path
      expect(JSON.parse(response.body)["count"]).to eq(0)
    end

    it "leaves a ticket that is not failed alone" do
      post handle_pos_print_log_path(log), as: :json
      expect(log.reload.status).to eq("pending")
    end

    it "refuses another company's ticket" do
      other_company = create(:company)
      stranger = create(:user, company: other_company, role: "cashier")
      log.update!(status: "failed")
      sign_in stranger

      post handle_pos_print_log_path(log), as: :json
      expect(log.reload.status).to eq("failed")
    end
  end

  describe "retry" do
    before { log.update!(status: "failed", error_message: "boom", claimed_at: Time.current, claimed_by: "x") }

    it "puts the job back in the queue and announces it on the branch stream" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_append_to)
        .with("pos_prints_#{company.id}_#{branch.id}", hash_including(target: "client-print-queue"))

      post retry_pos_print_log_path(log), as: :json

      expect(response).to have_http_status(:ok)
      log.reload
      expect([log.status, log.error_message, log.claimed_at, log.claimed_by]).to eq(["pending", nil, nil, nil])
    end

    it "leaves a job that is not failed alone" do
      log.update_columns(status: "sent")
      expect(Turbo::StreamsChannel).not_to receive(:broadcast_append_to)

      post retry_pos_print_log_path(log), as: :json
      expect(log.reload.status).to eq("sent")
    end
  end

  describe "order page" do
    it "shows the order's prints with a retry on the failed one" do
      log.update!(status: "failed", error_message: "Failed to fetch")

      get pos_order_path(order)
      expect(response.body).to include(retry_pos_print_log_path(log))
      expect(response.body).to include("Failed to fetch")
    end

    it "wires the register for recovery: failed pill, failed and retry urls" do
      Setting.set("print_routing", Printing::Config::ROUTING_CLIENT)

      get pos_order_path(order)
      expect(response.body).to include('id="print-failed-pill"')
      expect(response.body).to include(failed_pos_print_logs_path)
      expect(response.body).to include("data-client-printer-retry-url-template-value")
    end
  end
end
