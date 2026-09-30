class AddPartyToVouchers < ActiveRecord::Migration[7.1]
  def change
    add_reference :vouchers, :party, polymorphic: true, type: :uuid
  end
end
