# frozen_string_literal: true

# Orders are only placed against an open drawer. A request spec that rings one up
# opens a drawer for the cashier first.
module OpenDrawerHelpers
  def open_drawer_for(user, location:)
    company = user.company
    till = Treasury.create!(company: company, name: "Till #{SecureRandom.hex(3)}", treasury_type: "cash_drawer",
                            balance_cents: 0, opening_balance_cents: 0)
    CashDrawerSession.create!(company: company, user: user, treasury: till, location: location,
                              session_date: BusinessDay.today(location: location), opening_float_cents: 0,
                              status: "open")
  end
end

RSpec.configure { |config| config.include OpenDrawerHelpers, type: :request }
