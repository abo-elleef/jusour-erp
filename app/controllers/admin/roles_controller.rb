# frozen_string_literal: true

module Admin
  class RolesController < BaseController
    before_action :set_role, only: %i[edit update destroy]

    def index
      authorize Role
      @roles = policy_scope(Role).ordered
      @user_counts = User.where.not(role_id: nil).group(:role_id).count
    end

    def new
      @role = Role.new(permissions: [])
      authorize @role
    end

    def create
      @role = Role.new(role_params)
      authorize @role
      if @role.save
        redirect_to admin_roles_path, notice: t("flash.role.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @role
    end

    def update
      authorize @role
      if @role.update(role_params)
        redirect_to admin_roles_path, notice: t("flash.role.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @role
      if @role.destroy
        redirect_to admin_roles_path, notice: t("flash.role.deleted")
      else
        redirect_to admin_roles_path, alert: @role.errors.full_messages.to_sentence
      end
    end

    private

    def set_role
      @role = Role.find(params[:id])
    end

    def role_params
      permitted = params.require(:role).permit(:name, permissions: [])
      # Built-in role names are locked — their key drives the app.
      permitted.delete(:name) if @role&.built_in?
      permitted
    end
  end
end
