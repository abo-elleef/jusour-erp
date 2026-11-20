# frozen_string_literal: true

# Customer tickets — complaints and customer-satisfaction cases a staff member
# opens on a customer's behalf (Bazzar slice G1). One timeline per ticket:
# ticket_comments holds both people's comments and the system entries for
# status changes and reassignments.
class CreateTickets < ActiveRecord::Migration[7.1]
  def change
    create_table :ticket_categories, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      # Set on the seeded categories only, so a later migration can find them.
      t.string  :key
      t.string  :name, null: false
      t.string  :name_ar
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      # Who gets a new ticket in this category when nobody is picked.
      t.references :default_handler, type: :uuid, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :ticket_categories, %i[company_id key], unique: true, where: "key IS NOT NULL"

    create_table :tickets, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.integer :number, null: false
      t.references :customer, type: :uuid, null: false, foreign_key: true
      t.references :customer_invoice, type: :uuid, null: true, foreign_key: true
      t.references :credit_note, type: :uuid, null: true, foreign_key: true
      t.references :ticket_category, type: :uuid, null: true, foreign_key: true
      t.string :priority, null: false, default: "normal"
      t.string :status, null: false, default: "open"
      t.string :subject, null: false
      t.text   :description
      t.references :assigned_user, type: :uuid, null: true, foreign_key: { to_table: :users }
      t.references :opened_by, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.datetime :resolved_at
      t.datetime :closed_at
      t.timestamps
    end
    add_index :tickets, %i[company_id number], unique: true
    add_index :tickets, %i[company_id status]

    create_table :ticket_comments, id: :uuid do |t|
      t.references :ticket, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: true, foreign_key: true
      # comment | status_change | assignment_change
      t.string :kind, null: false, default: "comment"
      t.text   :body
      # System entries keep their facts (from/to status, user ids and names)
      # here and are worded at render time, in the reader's language.
      t.jsonb  :data, null: false, default: {}
      t.timestamps
    end
    add_index :ticket_comments, %i[ticket_id created_at]

    # Opening / resolving / closing a ticket shows on the customer's timeline
    # (slice F) as a system entry linking to the ticket.
    add_reference :customer_activities, :ticket, type: :uuid, null: true,
      foreign_key: { on_delete: :nullify }
  end
end
