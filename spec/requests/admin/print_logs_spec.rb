# frozen_string_literal: true

require "rails_helper"

# The admin "Print jobs" page: failures from every branch, kept after the POS pill
# drops them.
RSpec.describe "Admin print jobs", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch_a) { create(:location, company: company, name: "Downtown") }
  let!(:branch_b) { create(:location, company: company, name: "Mall") }
  let(:owner) { create(:user, company: company, role: "owner") }
  let(:cashier) { create(:user, company: company, role: "cashier") }

  def printer_for(branch, name)
    Printer.create!(company: company, location: branch, name: name, printer_type: "kitchen", station: name,
                    connection_type: "network", host: "192.168.1.60", port: 9100, paper_width: "80mm", active: true)
  end

  def job(branch, printer, status:, created_at: 1.hour.ago, error: nil)
    order = create(:order, user: owner, company: company, location: branch, status: "submitted")
    PrintLog.create!(order: order, printer: printer, print_type: "kitchen", status: status,
                     error_message: error).tap { |l| l.update_columns(created_at: created_at, updated_at: created_at) }
  end

  let!(:grill) { printer_for(branch_a, "Grill") }
  let!(:bar) { printer_for(branch_b, "Bar") }
  let!(:old_failure) { job(branch_a, grill, status: "failed", created_at: 3.days.ago, error: "Connection timed out") }
  let!(:mall_failure) { job(branch_b, bar, status: "failed", error: "ECONNREFUSED") }
  let!(:printed) { job(branch_a, grill, status: "sent") }

  before do
    Current.company = company
    sign_in owner
  end

  def row_ids = response.body.scan(/id="print_log_([0-9a-f-]{36})"/).flatten

  it "lists failures from every branch, older than the POS 12-hour window" do
    get admin_print_logs_path

    expect(response).to have_http_status(:ok)
    expect(row_ids).to contain_exactly(old_failure.id, mall_failure.id)
    expect(response.body).to include("Connection timed out")
  end

  it "drops a failure that was reprinted later from the default view" do
    PrintLog.create!(order: old_failure.order, printer: grill, print_type: "kitchen", status: "sent")

    get admin_print_logs_path
    expect(row_ids).to contain_exactly(mall_failure.id)

    get admin_print_logs_path(status: "failed")
    expect(row_ids).to include(old_failure.id)
    expect(response.body).to include(I18n.t("print_logs.reprinted_later"))
  end

  it "filters by branch, printer and date" do
    get admin_print_logs_path(location_id: branch_b.id)
    expect(row_ids).to contain_exactly(mall_failure.id)

    get admin_print_logs_path(printer_id: grill.id)
    expect(row_ids).to contain_exactly(old_failure.id)

    get admin_print_logs_path(from: Date.current.iso8601)
    expect(row_ids).to contain_exactly(mall_failure.id)
  end

  it "shows every status when asked" do
    get admin_print_logs_path(status: "all")
    expect(row_ids).to contain_exactly(old_failure.id, mall_failure.id, printed.id)
  end

  it "sorts by branch" do
    get admin_print_logs_path(sort: "branch", dir: "desc")
    expect(row_ids).to eq([mall_failure.id, old_failure.id])
  end

  it "does not show another company's jobs" do
    other = create(:company)
    other_branch = create(:location, company: other)
    other_user = create(:user, company: other, role: "owner")
    other_order = Current.set(company: other) do
      create(:order, user: other_user, company: other, location: other_branch, status: "submitted")
    end
    foreign = PrintLog.create!(order: other_order, print_type: "receipt", status: "failed")

    get admin_print_logs_path(status: "all")
    expect(row_ids).not_to include(foreign.id)

    post retry_admin_print_log_path(foreign)
    expect(response).to have_http_status(:not_found)
  end

  it "requeues a failed job" do
    post retry_admin_print_log_path(mall_failure), as: :turbo_stream

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(target="print_log_#{mall_failure.id}"))
    expect(mall_failure.reload.status).to eq("pending")
  end

  it "marks a failed job as handled" do
    post handle_admin_print_log_path(mall_failure)

    expect(mall_failure.reload.status).to eq("handled")
  end

  it "leaves a job that is not failed alone" do
    post handle_admin_print_log_path(printed)

    expect(printed.reload.status).to eq("sent")
  end

  it "is closed to cashiers" do
    sign_in cashier
    get admin_print_logs_path

    expect(response).not_to have_http_status(:ok)
  end
end
