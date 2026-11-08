class AddTableCountToLocations < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :table_count, :integer
  end
end
