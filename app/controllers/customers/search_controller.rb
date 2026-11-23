# frozen_string_literal: true

module Customers
  class SearchController < ApplicationController
    before_action :require_pos_access!

    def index
      return render_phone_match if request.format.json?

      @customers = if params[:q].to_s.strip.length >= 2
                     Customer.ransack(name_or_email_or_phone_or_phone_secondary_cont: params[:q].strip)
                             .result.order(:name, :phone)
                             .limit(10)
                   else
                     Customer.none
                   end
      render layout: false
    end

    private

    PICKUP_SUGGESTIONS = 5

    # The pickup phone popup searches as the cashier types: 4+ digits match any
    # part of a phone, 2+ letters match the name (Egyptian numbers share their
    # 01x prefix, so fewer digits would match half the customer list). `exact` is
    # the customer the full number belongs to, if any: that is the only one Enter
    # picks without the cashier moving to it (pickup_customer_controller.js).
    def render_phone_match
      query = params[:q].to_s.strip
      digits = query.gsub(/[\s-]+/, "")
      scope = if digits.match?(/\A\+?\d{4,}\z/)
                Customer.where("customers.phone LIKE :q OR customers.phone_secondary LIKE :q",
                               q: "%#{Customer.sanitize_sql_like(digits)}%")
              elsif query.length >= 2 && !query.match?(/\d/)
                Customer.where("customers.name ILIKE ?", "%#{Customer.sanitize_sql_like(query)}%")
              else
                Customer.none
              end
      exact = Customer.find_by(phone: digits) || Customer.find_by(phone_secondary: digits) if digits.match?(/\A\+?\d{8,}\z/)
      results = scope.order(:name, :phone).limit(PICKUP_SUGGESTIONS).to_a
      results = ([exact] + results).uniq.first(PICKUP_SUGGESTIONS) if exact

      render json: { exact: exact && pickup_json(exact), results: results.map { |c| pickup_json(c) } }
    end

    # name is the customer's own (may be blank); label is what the popup shows.
    def pickup_json(customer)
      { id: customer.id, name: customer.name.to_s, phone: customer.phone.to_s,
        label: customer.name.presence || customer.phone }
    end

    def require_pos_access!
      return if current_user&.cashier? || current_user&.admin_access?

      head :forbidden
    end
  end
end
