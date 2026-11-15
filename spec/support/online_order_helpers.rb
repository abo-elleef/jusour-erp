# frozen_string_literal: true

# A branch that takes self-orders, with one item and one delivery area.
module OnlineOrderHelpers
  def online_branch(company)
    create(:location, company: company, public_menu_enabled: true, online_ordering_enabled: true,
                      whatsapp_number: "01000000000")
  end

  def online_params(item:, area: nil, **overrides)
    {
      customer_name: "Mona", phone: "+20 100 123 4567",
      fulfillment: area ? "delivery" : "pickup",
      delivery_area_id: area&.id, address: area ? "12 Nile St, flat 4" : nil,
      items: [{ "menu_item_id" => item.id, "quantity" => 2 }],
      website: "", started_at: OnlineOrders::SubmitService.page_stamp(1.minute.ago)
    }.merge(overrides)
  end
end

RSpec.configure { |config| config.include OnlineOrderHelpers }
