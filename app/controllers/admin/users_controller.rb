# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    include StaffLocationFilter

    before_action :set_user, only: %i[show statement edit update destroy activate create_assigned_treasury]
    before_action :load_drawer_treasuries, only: %i[new create edit update]

    def index
      authorize User
      load_staff_location_filter

      scope = policy_scope(User)
      @q = apply_staff_location_filter(scope).ransack(params[:q])
      @sort = parse_index_sort_param
      @sort_direction = parse_index_sort_direction_param
      @total_count = scope.count
      @owner_count = scope.where(role: "owner").count
      @manager_count = scope.where(role: "manager").count
      @accountant_count = scope.where(role: "accountant").count
      @cashier_count = scope.where(role: "cashier").count
      @kitchen_count = scope.where(role: "kitchen").count
      @filtered = ransack_filtered? || @location_filter.present?
      @pagy, @users = pagy(:offset, @q.result.order(@sort => @sort_direction), limit: 25)
    end

    def new
      @user = User.new(role: "cashier")
      authorize @user
    end

    def create
      @user = User.new(user_params)
      authorize @user

      if @user.save
        redirect_to admin_user_path(@user), notice: t("flash.user.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    # The page is a shell (the header) plus one Turbo frame that
    # lazily loads the active tab from this same URL. A frame request gets
    # just that tab; anything else gets the shell. Payroll and Statement are
    # money, so they appear only for admin-access users, as before.
    TABS = %w[overview payroll statement history].freeze
    FINANCE_TABS = %w[payroll statement].freeze
    TAB_FRAME = "user_tab"

    def show
      authorize @user
      @tabs = visible_tabs
      @tab = requested_tab

      return unless turbo_frame_request_id == TAB_FRAME

      send(:"load_#{@tab}_tab")
      render "tab", layout: "turbo_rails/frame"
    end

    # Printable statement of account for the same date range as the tab.
    def statement
      authorize @user, :show?
      return redirect_to admin_user_path(@user), alert: t("flash.unauthorized") unless current_user.admin_access?

      load_statement
    end

    def edit
      authorize @user
    end

    def update
      authorize @user
      attributes = user_params
      attributes = attributes.except(:password, :password_confirmation) if attributes[:password].blank?

      if @user.update(attributes)
        redirect_to admin_user_path(@user), notice: t("flash.user.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @user
      @user.deactivate!
      redirect_to admin_users_path, notice: t("flash.user.deactivated")
    end

    def activate
      authorize @user
      @user.activate!
      redirect_to admin_user_path(@user), notice: t("flash.user.activated")
    end

    def create_assigned_treasury
      authorize @user, :update?

      unless current_user.owner? || current_user.accountant?
        return redirect_to admin_user_path(@user), alert: t("flash.unauthorized")
      end

      if @user.assigned_treasury_id.present?
        return redirect_to edit_admin_user_path(@user), alert: t("flash.user.assigned_treasury_exists")
      end

      treasury = Treasury.create_staff_drawer!(user_name: @user.name)
      @user.update!(assigned_treasury: treasury)
      redirect_to edit_admin_user_path(@user), notice: t("flash.user.assigned_treasury_created", name: treasury.name)
    rescue ActiveRecord::RecordInvalid => e
      redirect_to edit_admin_user_path(@user), alert: e.record.errors.full_messages.to_sentence
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def load_drawer_treasuries
      @drawer_treasuries = Treasury.active.cash_drawers.ordered
    end

    def visible_tabs
      current_user.admin_access? ? TABS : TABS - FINANCE_TABS
    end

    # Links from payroll pages (attendance, monthly payroll, the payroll
    # actions' redirects) carry payroll_month but no tab; they mean Payroll.
    def requested_tab
      tab = params[:tab].presence
      tab ||= "payroll" if params[:payroll_month].present?
      @tabs.include?(tab) ? tab : @tabs.first
    end

    def load_overview_tab; end

    def load_payroll_tab
      @payroll_month = parse_payroll_month
      @payroll_sort = parse_payroll_sort_param
      @payroll_direction = parse_payroll_direction_param
      @payroll_summary = @user.monthly_payroll(@payroll_month, sort: @payroll_sort, direction: @payroll_direction)
      @treasuries = Treasury.active.payable.visible_to(current_user).ordered
      @default_treasury = Treasury.default_treasury
      load_attendance_audits
    end

    def load_statement_tab
      load_statement
    end

    def load_history_tab
      @audits = @user.audits.includes(:user).reorder(version: :desc)
    end

    # This employee's own current account (see User#account_code): months
    # finalized credit it, vouchers paid to them and staff meals debit it,
    # vouchers received from them credit it. Dates are URL params (not the
    # session range the accounting pages share), defaulting to the year so far;
    # a reversed range is swapped rather than shown empty.
    def load_statement
      start_date = statement_date_param(:start_date) || Date.current.beginning_of_year
      end_date = statement_date_param(:end_date) || Date.current
      start_date, end_date = end_date, start_date if start_date > end_date
      @statement = ::Accounting::StaffStatementService.new(@user, from: start_date, to: end_date)
    end

    def statement_date_param(key)
      Date.iso8601(params[key].to_s)
    rescue ArgumentError
      nil
    end

    # Every change (create/clear/re-set) to this staff member's attendance for
    # the selected month — same ledger the grid's per-day "View history" reads,
    # just scoped to a whole month in one place. Same trust level as that.
    def load_attendance_audits
      return unless Current.company&.feature_enabled?(:attendance) && current_user.can?("attendance:audit")

      record_ids = @user.staff_attendances.for_month(@payroll_month).pluck(:id)
      @attendance_audits = AuditLogEntry.where(record_type: "StaffAttendance", record_id: record_ids)
        .includes(:user).order(created_at: :desc)
    end

    def parse_index_sort_param
      sort = params[:sort].to_s
      User::INDEX_SORTABLE_COLUMNS.include?(sort) ? sort : User::INDEX_DEFAULT_SORT
    end

    def parse_index_sort_direction_param
      params[:direction].to_s == "desc" ? "desc" : User::INDEX_DEFAULT_SORT_DIRECTION
    end

    def parse_payroll_sort_param
      sort = params[:payroll_sort].to_s
      PayrollAdjustment::SORTABLE_COLUMNS.include?(sort) ? sort : PayrollAdjustment::DEFAULT_SORT
    end

    def parse_payroll_direction_param
      params[:payroll_direction].to_s == "asc" ? "asc" : PayrollAdjustment::DEFAULT_SORT_DIRECTION
    end

    def ransack_filtered?
      params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
    end

    def user_params
      permitted = %i[name email pin]
      permitted += %i[role_id monthly_salary_pounds balance_deduction_pounds all_locations employment_start_on employment_end_on] if current_user.owner?
      permitted += %i[assigned_treasury_id] if current_user.owner? || current_user.accountant?
      changing_password = action_name == "create" || params.dig(:user, :password).present?
      permitted += %i[password password_confirmation] if changing_password

      permit_args = permitted.dup
      permit_args << { location_ids: [] } if current_user.owner?

      attrs = params.require(:user).permit(*permit_args)
      attrs[:location_ids] = Array(attrs[:location_ids]).reject(&:blank?) if attrs.key?(:location_ids)
      attrs[:role] = sanitize_role(attrs[:role]) if attrs[:role].present?
      attrs.delete(:pin) if attrs[:pin].blank?
      attrs.delete(:assigned_treasury_id) if attrs[:assigned_treasury_id].blank?
      attrs
    end

    def sanitize_role(role)
      return role if current_user.owner?

      policy(User).permitted_roles.include?(role) ? role : (@user&.role.presence || "cashier")
    end
  end
end
