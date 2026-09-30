# frozen_string_literal: true

# A shared "who" for money-movement records that otherwise carry only a
# category and a free-text description. Mirrors PaymentAllocation#settles: a
# polymorphic reference across models with no interface in common, which is
# why PartyHelper (party_label/party_path) exists rather than calling #name
# directly — the same reason SettledRecordsHelper exists for #settles.
#
# Adding a type to PARTY_TYPES is a decision, not a schema change: it needs an
# entry in PartyHelper, and in Accounting::PartyOptions if it should appear in
# the picker.
module Partyable
  extend ActiveSupport::Concern

  PARTY_TYPES = %w[Supplier Customer Partner User].freeze

  included do
    belongs_to :party, polymorphic: true, optional: true
    validates :party_type, inclusion: { in: PARTY_TYPES }, allow_nil: true
  end

  # "Supplier:<id>" as the searchable-select's hidden field carries it.
  def party_selection
    party_type.present? ? "#{party_type}:#{party_id}" : ""
  end

  def party_selection=(value)
    type, id = value.to_s.split(":", 2)
    self.party_type = type.presence
    self.party_id = type.present? ? id : nil
  end
end
