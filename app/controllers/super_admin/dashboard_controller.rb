# frozen_string_literal: true

module SuperAdmin
  class DashboardController < BaseController
    def index
      @companies = Company.unscoped
        .joins("LEFT JOIN locations ON locations.company_id = companies.id")
        .joins("LEFT JOIN users ON users.company_id = companies.id AND users.role = 'owner'")
        .joins("LEFT JOIN orders ON orders.company_id = companies.id AND orders.status NOT IN ('draft', 'voided')")
        .group("companies.id")
        .select(
          "companies.*",
          "COUNT(DISTINCT locations.id) AS locations_count",
          "COUNT(DISTINCT users.id) AS owners_count",
          "COUNT(DISTINCT orders.id) AS orders_count",
          "COALESCE(SUM(orders.total_cents), 0) AS revenue_cents"
        )
        .order("companies.name ASC")
    end
  end
end
