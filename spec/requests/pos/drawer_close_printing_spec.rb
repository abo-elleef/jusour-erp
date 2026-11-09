# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Printing the drawer closing slip", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Cafe") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:other_cashier) { create(:user, company: company, role: "cashier") }
  let(:manager) { create(:user, :manager, company: company) }
  let!(:till) do
    Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0)
  end
  let!(:printer) do
    Printer.create!(company: company, location: branch, name: "Front", printer_type: "receipt",
                    connection_type: "network", host: "192.168.1.50", port: 9100, paper_width: "80mm",
                    active: true, is_default: true)
  end

  before do
    Current.company = company
    Setting.set("print_routing", Printing::Config::ROUTING_CLIENT)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
  end

  def drawer_for(user, status: "open", counted: nil)
    CashDrawerSession.create!(company: company, user: user, treasury: till, location: branch,
                              session_date: BusinessDay.today(location: branch), opening_float_cents: 10_000,
                              status: status, expected_cash_cents: 10_000, counted_cash_cents: counted,
                              variance_cents: (counted ? counted - 10_000 : nil), created_at: 2.hours.ago)
  end

  describe "when the cashier counts and closes" do
    before do
      cashier.update!(assigned_treasury: till)
      sign_in cashier
    end

    it "queues the slip for printing" do
      drawer = drawer_for(cashier)

      expect { patch reconcile_pos_shift_path, params: { counted_cash: "100.00" } }
        .to change { PrintLog.where(cash_drawer_session: drawer, print_type: "drawer_close").count }.by(1)

      expect(drawer.reload.status).to eq("reconciled")
    end

    it "closes without a slip, and without an error, when the branch has no printer" do
      printer.update!(active: false)
      drawer = drawer_for(cashier)

      patch reconcile_pos_shift_path, params: { counted_cash: "100.00" }

      expect(drawer.reload.status).to eq("reconciled")
      expect(PrintLog.where(cash_drawer_session: drawer).pluck(:status)).to eq(["skipped"])
    end
  end

  describe "reprinting from the POS shift screen" do
    before { sign_in cashier }

    it "queues another slip for the cashier's own counted drawer" do
      drawer = drawer_for(cashier, status: "reconciled", counted: 10_000)

      expect { post print_closing_slip_pos_shift_path(session_id: drawer.id) }
        .to change { PrintLog.where(cash_drawer_session: drawer).count }.by(1)

      expect(response).to redirect_to(pos_shift_path)
      expect(flash[:notice]).to eq(I18n.t("flash.pos.shift.closing_slip_queued"))
    end

    it "offers the button on a closed drawer" do
      drawer_for(cashier, status: "reconciled", counted: 10_000)
      get pos_shift_path
      expect(response.body).to include(I18n.t("pos.shift.print_closing_slip"))
    end

    it "refuses a drawer that has not been counted" do
      drawer = drawer_for(cashier)

      expect { post print_closing_slip_pos_shift_path(session_id: drawer.id) }.not_to change(PrintLog, :count)
      expect(flash[:alert]).to eq(I18n.t("flash.pos.shift.closing_slip_unavailable"))
    end

    it "refuses another cashier's drawer" do
      drawer = drawer_for(other_cashier, status: "reconciled", counted: 10_000)

      expect { post print_closing_slip_pos_shift_path(session_id: drawer.id) }.not_to change(PrintLog, :count)
      expect(flash[:alert]).to eq(I18n.t("flash.pos.shift.closing_slip_unavailable"))
    end
  end

  describe "from the admin" do
    before { sign_in manager }

    it "reprints a counted drawer to the branch and says so" do
      drawer = drawer_for(cashier, status: "reconciled", counted: 10_000)

      expect { post print_slip_admin_accounting_cash_drawer_path(drawer) }
        .to change { PrintLog.where(cash_drawer_session: drawer).count }.by(1)
      expect(flash[:notice]).to eq(I18n.t("flash.accounting.drawer_slip_queued"))
    end

    it "shows the button on the details page only once the drawer is counted" do
      counted = drawer_for(cashier, status: "reconciled", counted: 10_000)
      get admin_accounting_cash_drawer_path(counted)
      expect(response.body).to include(print_slip_admin_accounting_cash_drawer_path(counted))

      open_drawer = drawer_for(other_cashier)
      get admin_accounting_cash_drawer_path(open_drawer)
      expect(response.body).not_to include(print_slip_admin_accounting_cash_drawer_path(open_drawer))
    end

    it "prints a slip when the manager counts the drawer from the admin" do
      drawer = drawer_for(cashier)

      expect { patch reconcile_admin_accounting_cash_drawer_path(drawer), params: { counted_cash: "100.00" } }
        .to change { PrintLog.where(cash_drawer_session: drawer).count }.by(1)
    end
  end

  describe "the print agent's endpoints" do
    let(:drawer) { drawer_for(cashier, status: "reconciled", counted: 10_000) }
    let!(:log) { PrintLog.create!(cash_drawer_session: drawer, printer: printer, print_type: "drawer_close", status: "pending") }

    before { sign_in cashier }

    it "offers a pending slip to a register at that branch" do
      get pending_pos_print_logs_path
      expect(JSON.parse(response.body).map { |j| j["id"] }).to include(log.id)
    end

    it "hands out the slip's payload, to one register only" do
      get payload_pos_print_log_path(log, client_id: "register-a")
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["print_type"]).to eq("drawer_close")
      expect(Base64.decode64(body["data_base64"])).not_to be_empty

      get payload_pos_print_log_path(log, client_id: "register-b")
      expect(response).to have_http_status(:conflict)
    end

    it "keeps a slip addressed to one register away from the others" do
      ws_a = Workstation.create!(company: company, location: branch, name: "A", active: true)
      ws_b = Workstation.create!(company: company, location: branch, name: "B", active: true)
      log.update!(workstation: ws_a)

      sign_in cashier
      get pos_shift_path # sets a session
      allow_any_instance_of(Pos::PrintLogsController).to receive(:session).and_return(
        { pos_location_id: branch.id, pos_workstation_id: ws_b.id }.with_indifferent_access
      )
      get pending_pos_print_logs_path
      expect(JSON.parse(response.body).map { |j| j["id"] }).not_to include(log.id)
    end

    it "does not hand a slip to another company's user" do
      stranger_company = create(:company)
      Current.company = stranger_company
      stranger = create(:user, company: stranger_company, role: "cashier")
      sign_out cashier
      sign_in stranger

      get payload_pos_print_log_path(log, client_id: "x")
      expect(response).not_to have_http_status(:ok)
    end
  end
end
