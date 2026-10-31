# frozen_string_literal: true

# The staff member page loads its active tab lazily into a Turbo frame. A plain
# GET returns only the shell; asking as the frame returns the tab itself.
module UserTabHelpers
  def get_user_tab(user, tab, **params)
    get admin_user_path(user, params.merge(tab: tab)),
      headers: { "Turbo-Frame" => Admin::UsersController::TAB_FRAME }
  end
end

RSpec.configure do |config|
  config.include UserTabHelpers, type: :request
end
