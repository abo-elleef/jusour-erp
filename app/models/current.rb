# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :company
  # Who is acting in this request — set by the sales area so stage
  # notifications don't tell people about their own changes.
  attribute :user
end
