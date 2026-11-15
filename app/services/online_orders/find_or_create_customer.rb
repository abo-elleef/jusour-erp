# frozen_string_literal: true

module OnlineOrders
  # The customer behind a self-order, created on first accept (or block) only, so
  # spam that never gets accepted leaves no customer rows behind. Survives two
  # registers racing on the same new phone, like Orders::SyncOfflineOrderService.
  module FindOrCreateCustomer
    module_function

    def call(request)
      return request.customer if request.customer

      customer = lookup(request.phone) || create(request)
      request.update!(customer: customer)
      customer
    end

    def lookup(phone)
      variants = Phones::EgyptianMobile.variants(phone)
      Customer.where(phone: variants).or(Customer.where(phone_secondary: variants)).first
    end

    def create(request)
      Customer.transaction(requires_new: true) do
        Customer.create!(name: request.customer_name, phone: request.phone)
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      lookup(request.phone) || raise
    end
  end
end
