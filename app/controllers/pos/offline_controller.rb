# frozen_string_literal: true

module Pos
  # The register that keeps working when the internet does not.
  #
  # `show` is a thin shell the service worker keeps cached; everything on it is
  # drawn in the browser from the snapshot `snapshot` hands out while online. Orders
  # rung up offline come back through `create_order`, one at a time, once the
  # connection returns.
  class OfflineController < ApplicationController
    include PosLocationScoped
    include FeatureGated

    layout "pos_offline"

    before_action { require_feature!(:menu) }
    before_action :require_pos_access!
    before_action :no_store

    def show; end

    def snapshot
      authorize Order, :create?

      render json: Orders::OfflineSnapshotService.call(
        user: current_user,
        location: @pos_location,
        workstation: @pos_workstation,
        csrf_token: form_authenticity_token
      )
    end

    def create_order
      authorize Order, :create?

      result = Orders::SyncOfflineOrderService.call(user: current_user, payload: order_params.to_h)

      if result.success?
        render json: {
          success: true,
          duplicate: result.duplicate?,
          order_id: result.order.id,
          order_number: result.order.order_number
        }, status: result.duplicate? ? :ok : :created
      else
        render json: { success: false, errors: result.errors }, status: :unprocessable_entity
      end
    end

    private

    def order_params
      params.require(:order).permit(
        :client_uuid, :offline_number, :created_at, :order_type, :table_number, :notes,
        :customer_name, :customer_phone, :delivery_address,
        :user_id, :location_id, :workstation_id, :drawer_session_id, :tendered_cents, :replaces_order_id,
        items: [
          :menu_item_id, :combo_id, :quantity, :unit_price_cents, :notes,
          :promo_id, :promo_label, :promo_discount_cents,
          { modifiers: %i[id name price_adjustment_cents] }
        ]
      )
    end

    def require_pos_access!
      return if current_user&.can_access_pos?

      respond_to do |format|
        format.json { render json: { error: t("flash.pos_access") }, status: :forbidden }
        format.any do
          flash[:alert] = t("flash.pos_access")
          redirect_to root_path
        end
      end
    end

    def no_store
      response.headers["Cache-Control"] = "no-store"
    end
  end
end
