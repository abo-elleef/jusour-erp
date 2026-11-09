# frozen_string_literal: true

# No order is placed, and no money is taken against one, unless the cashier has a
# drawer open. An order rung up before the drawer exists belongs to no shift: it
# falls outside the count, drops out of the shift's orders, and a digital payment on
# it never reaches the wallet when the drawer is closed. Catching it at the till is
# the only place it can be fixed without a manager and a correction afterwards.
module OpenDrawerGate
  extend ActiveSupport::Concern

  private

  # `location` narrows the check to one branch; without it any open drawer of the
  # cashier's counts, as the cash check always has.
  def require_open_drawer_to_order!(location: nil)
    return if current_user.open_cash_drawer_session(location: location)

    refuse_without_drawer(t("flash.pos.shift.no_open_drawer_to_order"))
  end

  # The menu's add buttons and the order drawer post from inside the register page, so
  # a redirect would be swallowed by the frame and the cashier would see nothing. For
  # those, say it where they are; a full-page form is sent to open the drawer.
  def refuse_without_drawer(message)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("toast-container", partial: "shared/toast",
                                                                      locals: { message: message, type: :alert }),
               status: :unprocessable_entity
      end
      format.any { redirect_to pos_shift_path(tab: "shift"), alert: message, status: :see_other }
    end
  end
end
