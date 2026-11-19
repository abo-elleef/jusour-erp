# frozen_string_literal: true

module Admin
  class RolesController < BaseController
    before_action :set_role, only: %i[edit update destroy]

    def index
      authorize Role
      @roles = policy_scope(Role).ordered
      @user_counts = User.where.not(role_id: nil).group(:role_id).count
    end

    # `copy_from` opens the form pre-filled from an existing role (name +
    # permissions) so a near-identical role is a few ticks away. Staff are
    # never copied.
    def new
      @source_role = Role.find_by(id: params[:copy_from]) if params[:copy_from].present?
      @role = if @source_role
        Role.new(name: t("roles.copy_name", name: @source_role.name), permissions: @source_role.permission_keys)
      else
        Role.new(permissions: [])
      end
      authorize @role
    end

    def create
      @role = Role.new(role_params)
      @source_role = Role.find_by(id: params[:copy_from]) if params[:copy_from].present?
      authorize @role
      saved = Role.transaction do
        @role.save && (copy_role_settings(@source_role, @role) || true)
      end
      if saved
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

    # Role-level settings that live outside the role row: the sales
    # invoice-stage grid (what the role sees / is notified about).
    def copy_role_settings(source, role)
      return unless source

      source.stage_accesses.each do |access|
        role.stage_accesses.create!(stage: access.stage, can_see: access.can_see, notify: access.notify)
      end
    end

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
