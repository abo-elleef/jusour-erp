# frozen_string_literal: true

# A blocked customer cannot place self-orders from the public menu. Who and why
# are kept so the block can be reviewed and lifted.
class AddBlockingToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :customers, :blocked_at, :datetime
    add_column :customers, :blocked_reason, :text
    add_reference :customers, :blocked_by, type: :uuid, foreign_key: { to_table: :users }
  end
end
