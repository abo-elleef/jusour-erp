# frozen_string_literal: true

class Company < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :locations, dependent: :destroy
  has_many :orders, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
  validates :timezone, :currency, :locale, presence: true

  def self.ransackable_attributes(_auth_object = nil)
    %w[name slug active created_at]
  end
end
