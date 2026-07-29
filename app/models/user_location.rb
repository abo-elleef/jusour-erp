# frozen_string_literal: true

# Join between a user and the locations they're scoped to. Only consulted when
# the user is NOT `all_locations` — it's the "where" half of authorization
# (permissions being the "what").
class UserLocation < ApplicationRecord
  belongs_to :user
  belongs_to :location

  validates :location_id, uniqueness: { scope: :user_id }
end
