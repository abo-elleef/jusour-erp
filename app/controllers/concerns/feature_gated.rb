# frozen_string_literal: true

# Defense-in-depth for feature gating: a module switched off for this company's
# business profile can't be reached by direct URL even though its nav is hidden.
# A dental distributor has no menu, no kitchen and no tickets; a restaurant has no
# credit sales. Use as `before_action { require_feature!(:menu) }`.
module FeatureGated
  extend ActiveSupport::Concern

  private

  def require_feature!(feature)
    return if Current.company&.feature_enabled?(feature)

    flash[:alert] = t("flash.feature_unavailable", default: "That feature isn't available for your business type.")
    redirect_to feature_unavailable_redirect_path
  end

  # Admin screens fall back to the admin dashboard; everything else to the app root.
  def feature_unavailable_redirect_path
    self.class.name.start_with?("Admin::") ? admin_root_path : root_path
  end
end
