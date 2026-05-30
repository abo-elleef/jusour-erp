# frozen_string_literal: true

class OrderEvent < ApplicationRecord
  belongs_to :order
  belongs_to :user, optional: true
end
