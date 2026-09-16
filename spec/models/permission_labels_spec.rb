# frozen_string_literal: true

require "rails_helper"

# permission_label falls back to a humanized key, so a new permission ships looking
# fine in English and shows English text in the middle of the Arabic roles screen.
# This is the check that catches it at the point it is added.
RSpec.describe "Permission labels", type: :helper do
  %i[en ar].each do |locale|
    it "has a #{locale} label for every permission in the catalog" do
      missing = I18n.with_locale(locale) do
        Permission::KEYS.reject { |key| I18n.t("permissions.keys.#{key.tr(':', '.')}", default: nil) }
      end

      expect(missing).to be_empty, "missing #{locale} labels for: #{missing.join(', ')}"
    end
  end

  it "has a label for every permission group" do
    %i[en ar].each do |locale|
      missing = I18n.with_locale(locale) do
        Permission::GROUPS.reject { |g| I18n.t("permissions.groups.#{g}", default: nil) }
      end

      expect(missing).to be_empty, "missing #{locale} group labels for: #{missing.join(', ')}"
    end
  end
end
