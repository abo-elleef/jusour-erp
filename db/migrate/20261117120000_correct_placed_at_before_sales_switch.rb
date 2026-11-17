# frozen_string_literal: true

# Sales now count on the day an order was placed (placed_at), not the day its
# cart was opened. Two kinds of existing order carry a placed_at that is not
# when they were really placed, and would jump to the wrong day:
#
# - Offline orders: placed_at was stamped when the sync reached the server, not
#   when the till rang them up. The till's time is created_at.
# - Old drafts swept by "Complete all" months after they were opened (SAQR's
#   pre-launch June–August orders, placed 2026-11-11): the sweep stamped the
#   moment it ran. Nothing recorded a real placement, so they keep the day they
#   have always been reported on.
#
# Both get placed_at = created_at, which leaves every past day's figures as
# they were. Raw SQL on purpose: migrations must not depend on app models.
class CorrectPlacedAtBeforeSalesSwitch < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE orders SET placed_at = created_at
      WHERE placed_at IS NOT NULL
        AND (client_uuid IS NOT NULL OR placed_at - created_at > interval '7 days')
    SQL
  end

  def down
    # Data correction; the stamped times it replaced were not meaningful.
  end
end
