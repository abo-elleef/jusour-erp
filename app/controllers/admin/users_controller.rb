# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[edit update destroy]

    def index
      authorize User

      @q = User.ransack(params[:q])
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
        redirect_to admin_users_path, notice: "Staff member created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @user
    end

    def update
      authorize @user
      attributes = user_params
      attributes = attributes.except(:password, :password_confirmation) if attributes[:password].blank?

      if @user.update(attributes)
        redirect_to admin_users_path, notice: "Staff member updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @user
      @user.destroy
      redirect_to admin_users_path, notice: "Staff member removed."
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      permitted = %i[name email role]
      permitted += %i[password password_confirmation] if @user.new_record? || params.dig(:user, :password).present?

      attrs = params.require(:user).permit(permitted)
      attrs[:role] = sanitize_role(attrs[:role]) if attrs[:role].present?
      attrs
    end

    def sanitize_role(role)
      return role if current_user.owner?

      %w[cashier kitchen].include?(role) ? role : (@user.role.presence || "cashier")
    end
  end
end
