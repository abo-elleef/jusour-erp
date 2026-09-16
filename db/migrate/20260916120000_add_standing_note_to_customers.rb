# frozen_string_literal: true

# A note that belongs to the customer rather than to one order — an allergy, a
# gate code, "always extra napkins". It seeds the note on every new order they are
# attached to, so the kitchen sees it without the cashier retyping it.
#
# Deliberately NOT the existing `customers.notes`. That column was never surfaced
# in the app and its 128 rows came from the legacy import holding delivery
# landmarks ("above El-Ezaby pharmacy") that supplement a separate address row.
# Pointing order notes at it would print directions on kitchen tickets.
class AddStandingNoteToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :customers, :standing_note, :text
  end
end
