# frozen_string_literal: true

class AddReversalOfIdToJournalEntries < ActiveRecord::Migration[7.1]
  def change
    add_column :journal_entries, :reversal_of_id, :uuid, null: true
    add_index  :journal_entries, :reversal_of_id
    add_foreign_key :journal_entries, :journal_entries, column: :reversal_of_id
  end
end
