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

    # Exact stored shapes first (indexed); then the same number however a cashier
    # typed it — "010 6038 3589", "010-...", Arabic digits, or without its leading 0.
    def lookup(phone)
      variants = Phones::EgyptianMobile.variants(phone)
      return nil if variants.empty?

      Customer.where(phone: variants).or(Customer.where(phone_secondary: variants)).first ||
        loose_lookup(phone)
    end

    def loose_lookup(phone)
      digits = Phones::EgyptianMobile.digit_variants(phone)
      Customer.where("#{Phones::EgyptianMobile.digits_sql('customers.phone')} IN (?)", digits)
              .or(Customer.where("#{Phones::EgyptianMobile.digits_sql('customers.phone_secondary')} IN (?)", digits))
              .order(:created_at).first
    end

    def create(request)
      Customer.transaction(requires_new: true) do
        # The customer typed this number on the public menu; a length rule must
        # not stop a cashier from accepting their order.
        Customer.create!(name: request.customer_name, phone: request.phone, skip_phone_length_check: true)
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      lookup(request.phone) || raise
    end
  end
end
