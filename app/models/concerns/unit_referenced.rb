# frozen_string_literal: true

# Lets a model reference a company `Unit` by FK while still exposing the unit as
# a plain name string (the API the conversion helpers and views expect). The
# stored value is the `*_id` column; the string reader/writer are a thin facade.
#
#   references_unit :unit, column: :unit_id, required: true
#   references_unit :counted_unit, column: :counted_unit_id
#
# `record.unit`  -> the unit's name (or nil)
# `record.unit = "gallons"` (or a Unit) -> resolves within the current company
module UnitReferenced
  extend ActiveSupport::Concern

  class_methods do
    def references_unit(name, column:, required: false)
      assoc = :"#{name}_ref"
      # Presence is enforced (when required) via the name attribute, not the
      # association, so a missing/unknown unit surfaces on `:#{name}`.
      belongs_to assoc, class_name: "Unit", foreign_key: column, optional: true

      define_method(name) { public_send(assoc)&.name }

      # True when a non-blank name was assigned but matched no company unit.
      define_method("#{name}_unresolved?") { !!instance_variable_get(:"@#{name}_unresolved") }

      define_method("#{name}=") do |value|
        resolved =
          case value
          when Unit then value
          when nil, "" then nil
          else
            # Resolve within the record's own company when it has one (which may
            # differ from Current.company, e.g. during factory build); otherwise
            # fall back to the tenant-scoped Unit relation.
            rel = if respond_to?(:company_id) && company_id.present?
                    Unit.unscoped_by_company.where(company_id: company_id)
                  else
                    Unit.all
                  end
            rel.find_by("LOWER(name) = ?", value.to_s.downcase)
          end
        instance_variable_set(:"@#{name}_unresolved", value.present? && !value.is_a?(Unit) && resolved.nil?)
        public_send("#{assoc}=", resolved)
      end

      if required
        validate do
          if public_send("#{name}_unresolved?")
            errors.add(name, :not_available)
          elsif public_send(column).blank? && public_send(assoc).blank?
            errors.add(name, :blank)
          end
        end
      end
    end
  end
end
