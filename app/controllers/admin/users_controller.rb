# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[show edit update destroy activate]

    def index
      authorize User

      scope = policy_scope(User)
      @q = scope.ransack(params[:q])
      @sort = parse_index_sort_param
      @sort_direction = parse_index_sort_direction_param
      @total_count = scope.count
      @owner_count = scope.where(role: "owner").count
      @manager_count = scope.where(role: "manager").count
      @cashier_count = scope.where(role: "cashier").count
      @kitchen_count = scope.where(role: "kitchen").count
      @filtered = params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
      @pagy, @users = pagy(:offset, @q.result.order(@sort => @sort_direction), limit: 25)
      load_index_payroll_context
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

    private

    def set_user
      @user = User.find(params[:id])
    end

    def load_payroll_context
      return unless current_user.admin_access?

      @payroll_month = parse_payroll_month_param
      @payroll_sort = parse_payroll_sort_param
      @payroll_direction = parse_payroll_direction_param
      @payroll_summary = @user.monthly_payroll(@payroll_month, sort: @payroll_sort, direction: @payroll_direction)
      @treasuries = Treasury.active.payable.ordered
      @default_treasury = Treasury.default_treasury
    end

    def load_index_payroll_context
      return unless current_user.admin_access?

      @current_payroll_month = Date.current.beginning_of_month
      @treasuries = Treasury.active.payable.ordered
      @default_treasury = Treasury.default_treasury
      user_ids = @users.map(&:id)
      @payroll_snapshots_by_user = PayrollSnapshot.for_month(@current_payroll_month)
        .where(user_id: user_ids)
        .index_by(&:user_id)
      @payroll_remaining_by_user = {}
      @users.each do |staff|
        next if @payroll_snapshots_by_user[staff.id]

        @payroll_remaining_by_user[staff.id] =
          ::Accounting::MonthlyPayrollService.new(staff, @current_payroll_month).build_calculated.remaining_pay_cents
      end
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

    def parse_payroll_month_param
      if params[:payroll_month].present?
        Date.parse("#{params[:payroll_month]}-01")
      else
        Date.current.beginning_of_month
      end
    rescue ArgumentError
      Date.current.beginning_of_month
    end

    def user_params
      permitted = %i[name email role monthly_salary_cents pin]
      changing_password = action_name == "create" || params.dig(:user, :password).present?
      permitted += %i[password password_confirmation] if changing_password

      attrs = params.require(:user).permit(permitted)
      attrs[:role] = sanitize_role(attrs[:role]) if attrs[:role].present?
      attrs.delete(:pin) if attrs[:pin].blank?
      attrs
    end

    def sanitize_role(role)
      return role if current_user.owner?

      policy(User).permitted_roles.include?(role) ? role : (@user&.role.presence || "cashier")
    end
  end
end
