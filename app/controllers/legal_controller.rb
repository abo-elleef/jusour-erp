# frozen_string_literal: true

# Public legal pages. Open to everyone, including signed-out visitors and users
# of a locked company (they should still be able to read what they agreed to).
class LegalController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :enforce_subscription!
  layout "legal"

  def terms; end
end
