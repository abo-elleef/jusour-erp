# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[show edit update destroy]

    def index
      authorize User

      scope = policy_scope(User).active
      @q = scope.ransack(params[:q])
      @total_count = scope.count
      @owner_count = scope.where(role: "owner").count
      @manager_count = scope.where(role: "manager").count
      @cashier_count = scope.where(role: "cashier").count
      @kitchen_count = scope.where(role: "kitchen").count
      @filtered = params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
      @pagy, @users = pagy(:offset, @q.result.order(:name), limit: 25)
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

    private

    def set_user
      @user = User.find(params[:id])
    end

    def load_payroll_context
      return unless current_user.admin_access?

      @payroll_month = parse_payroll_month_param
      @payroll_summary = @user.monthly_payroll(@payroll_month)
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
      permitted += %i[password password_confirmation] if @user.new_record? || params.dig(:user, :password).present?

      attrs = params.require(:user).permit(permitted)
      attrs[:role] = sanitize_role(attrs[:role]) if attrs[:role].present?
      attrs.delete(:pin) if attrs[:pin].blank?
      attrs
    end

    def sanitize_role(role)
      return role if current_user.owner?

      policy(User).permitted_roles.include?(role) ? role : (@user.role.presence || "cashier")
    end
  end
end
