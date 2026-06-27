# frozen_string_literal: true

class SuperAdminUser < ApplicationRecord
  devise :database_authenticatable, :rememberable, :validatable

  validates :name, presence: true
end
