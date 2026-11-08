# frozen_string_literal: true

module Users
  class SessionsController < Devise::SessionsController
    layout "devise"

    # A fresh sign-in is never an impersonation; drop any leftover flag.
    def create
      session.delete(:impersonating)
      super
    end
  end
end
