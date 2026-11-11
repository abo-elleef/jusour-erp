# frozen_string_literal: true

# A promo can target one choice of the item (e.g. only the "Double" size).
# NULL keeps today's behaviour: the promo applies whatever was chosen.
class AddModifierToMenuPromos < ActiveRecord::Migration[7.1]
  def change
    add_reference :menu_promos, :modifier, type: :uuid, null: true, index: true,
                                           foreign_key: { on_delete: :cascade }
  end
end
