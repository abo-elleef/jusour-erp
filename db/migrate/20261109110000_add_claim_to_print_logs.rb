# frozen_string_literal: true

# A shared-branch print job reaches every open register; the first one to claim it
# prints it and the rest stand down. claimed_at expires, so a register that claims
# a job and then dies does not leave it stuck.
class AddClaimToPrintLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :print_logs, :claimed_at, :datetime
    add_column :print_logs, :claimed_by, :string
  end
end
