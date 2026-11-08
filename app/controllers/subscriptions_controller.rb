# frozen_string_literal: true

# Plain explanation page for signed-in users whose company is suspended or past
# its subscription grace period (see ApplicationController#enforce_subscription!).
class SubscriptionsController < ApplicationController
  skip_before_action :enforce_subscription!
  layout "devise"

  def locked
    company = Current.company
    return redirect_to(root_path) unless company&.access_blocked?

    @status = company.subscription_status
    @company = company
    @support_whatsapp = ENV["SUPPORT_WHATSAPP"].to_s.gsub(/\D/, "").presence
  end
end
