# frozen_string_literal: true

# سند قبض / سند صرف — the document for money actually crossing a treasury.
#
# A voucher carries its own date, independent of the date the income or expense
# it settles was booked. That separation is the whole point: an expense belongs
# to the month it was incurred, the cash to the month it left, and an accrued
# payable holds the difference in between.
#
# What it settles lives in payment_allocations, so one voucher can clear several
# things at once. Nothing is stored here about the balance remaining — that is
# the amount less its allocations.
class CreateVouchers < ActiveRecord::Migration[7.1]
  def change
    create_table :vouchers, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid   :company_id,   null: false
      # receipt = money in (سند قبض), payment = money out (سند صرف).
      t.string :direction,    null: false
      # RV-2026-00001 / PV-2026-00001 — separate books, as the two are kept
      # separately on paper, each resetting yearly like SI-, VI- and JE-.
      t.string :number,       null: false
      t.date   :voucher_date, null: false
      t.uuid   :treasury_id,  null: false
      t.uuid   :user_id,      null: false
      t.bigint :amount_cents, null: false
      t.text   :notes
      # Who the money came from or went to, when that is not already implied by
      # what the voucher settles — a name on a hand-written receipt.
      t.string :counterparty

      t.timestamps
    end

    add_index :vouchers, :company_id
    add_index :vouchers, %i[company_id number], unique: true
    add_index :vouchers, :voucher_date
    add_index :vouchers, :treasury_id
    add_index :vouchers, :direction

    add_foreign_key :vouchers, :companies
    add_foreign_key :vouchers, :treasuries
    add_foreign_key :vouchers, :users
  end
end
