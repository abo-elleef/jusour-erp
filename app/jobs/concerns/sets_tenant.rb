# frozen_string_literal: true

module SetsTenant
  extend ActiveSupport::Concern

  private

  def with_company(company)
    previous = Current.company
    Current.company = company
    yield
  ensure
    Current.company = previous
  end
end
