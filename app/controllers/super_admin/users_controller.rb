# frozen_string_literal: true

module SuperAdmin
  class UsersController < BaseController
    before_action :set_company

    def new
      @user = User.new(role: "owner")
    end

    def create
      @user = User.unscoped.new(user_params)
      @user.company = @company
      if @user.save
        redirect_to super_admin_company_path(@company), notice: "Owner account created."
      else
        render :new, status: :unprocessable_content
      end
    end

    private

    def set_company
      @company = Company.unscoped.find(params[:company_id])
    end

    def user_params
      params.require(:user).permit(:name, :email, :password, :password_confirmation, :role)
    end
  end
end
