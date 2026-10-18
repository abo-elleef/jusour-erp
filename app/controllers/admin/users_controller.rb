# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    include StaffLocationFilter

    before_action :set_user, only: %i[show edit update destroy activate create_assigned_treasury]
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

    def show
      authorize @user
      load_payroll_context
      @audits = @user.audits.includes(:user).reorder(version: :desc)
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

    def load_payroll_context
      return unless current_user.admin_access?

      @payroll_month = parse_payroll_month
      @payroll_sort = parse_payroll_sort_param
      @payroll_direction = parse_payroll_direction_param
      @payroll_summary = @user.monthly_payroll(@payroll_month, sort: @payroll_sort, direction: @payroll_direction)
      @treasuries = Treasury.active.payable.visible_to(current_user).ordered
      @default_treasury = Treasury.default_treasury
      load_wages_ledger
      load_attendance_audits
    end

    # This employee's own current account (see User#account_code): months
    # finalized credit it, vouchers paid to them and staff meals debit it,
    # vouchers received from them credit it. Same ledger shape as the
    # Loan/Partner show pages.
    def load_wages_ledger
      @wages_balance_cents = @user.staff_balance_cents
      @wages_lines = JournalEntryLine.joins(:journal_entry)
        .where(journal_entries: { company_id: Current.company.id })
        .where(account_code: @user.account_code)
        .includes(:journal_entry)
        .order("journal_entries.date DESC, journal_entries.entry_number DESC")
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
      permitted += %i[role_id monthly_salary_pounds all_locations] if current_user.owner?
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
