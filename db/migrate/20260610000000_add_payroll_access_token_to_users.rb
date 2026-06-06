# frozen_string_literal: true

class AddPayrollAccessTokenToUsers < ActiveRecord::Migration[7.1]
  def up
    add_column :users, :payroll_access_token, :string
    add_index :users, :payroll_access_token, unique: true

    User.reset_column_information
    User.find_each do |user|
      user.update_column(:payroll_access_token, SecureRandom.urlsafe_base64(24))
    end

    change_column_null :users, :payroll_access_token, false
  end

  def down
    remove_index :users, :payroll_access_token
    remove_column :users, :payroll_access_token
  end
end
