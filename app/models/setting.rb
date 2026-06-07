# frozen_string_literal: true

class Setting < ApplicationRecord
  include Tenantable

  validates :key, presence: true, uniqueness: { scope: :company_id }

  def self.get(key, default = nil)
    find_by(key: key)&.value || default
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.update!(value: value.to_s)
    record
  end

  def self.get_int(key, default = 0)
    get(key, default).to_i
  end
end
