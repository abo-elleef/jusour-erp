# frozen_string_literal: true

module Orders
  # Takes back what completing an order did, for an order voided after it was
  # completed. Only a never-paid order can get here (Order#never_paid?): a cart
  # left open and swept up by Complete all, say. A paid one is refunded instead.
  #
  # Completing did three things, and each is undone:
  # - stock: DeductStockService drew the recipe out of the branch. It is put back
  #   the same way, as a positive "consumption" row, so net consumption for the
  #   order is zero. The original rows carry only the order number, which repeats
  #   daily, so the quantities are rebuilt from the recipe rather than looked up.
  # - loyalty: points earned on the order are taken back off the customer.
  # - the books: the day's sales entry and cost-of-sales row are built from that
  #   day's completed orders. If the day was already posted, it is posted again
  #   without this order; a day not posted yet will leave it out when it is.
  class UndoCompletionService
    def self.call(order, user:)
      new(order, user: user).call
    end

    def initialize(order, user:)
      @order = order
      @user = user
    end

    def call
      restock!
      reverse_loyalty!
      repost_sales_day!
    end

    private

    def restock!
      ingredient_totals.each do |ingredient, quantity|
        next if quantity.zero?

        StockAdjustment.create!(
          ingredient: ingredient,
          user: @user,
          location: @order.location,
          quantity_delta: quantity,
          adjustment_type: "consumption",
          # Back in at the branch average, with a batch to hold it, so FIFO and
          # the on-hand figure agree.
          maintain_batches: true,
          reason_notes: "Voided Order #{@order.order_number} (#{business_date}) — stock returned"
        )
      end
    end

    # Same arithmetic as DeductStockService, summed across the order.
    def ingredient_totals
      totals = Hash.new(0)
      @order.order_items
            .includes(
              menu_item: { recipes: :ingredient },
              order_item_modifiers: { modifier: { modifier_recipes: :ingredient } }
            )
            .each do |item|
        next unless item.menu_item_id

        item.menu_item.recipes.each do |recipe|
          totals[recipe.ingredient] += recipe.base_quantity_used * item.quantity
        end
        item.order_item_modifiers.each do |oim|
          oim.modifier.modifier_recipes.each do |mr|
            totals[mr.ingredient] += mr.quantity.to_d * item.quantity
          end
        end
      end
      totals
    end

    def reverse_loyalty!
      customer = @order.customer
      return unless customer

      earned = LoyaltyTransaction.where(order: @order, transaction_type: "earned").sum(:points)
      return unless earned.positive?

      customer.loyalty_transactions.create!(
        order: @order,
        transaction_type: "adjusted",
        points: -earned,
        description: "Points reversed — #{@order.order_number} voided"
      )
      customer.decrement!(:loyalty_points, earned)
      customer.decrement!(:total_spent_cents, @order.total_cents - @order.tip_cents)
    end

    def repost_sales_day!
      location = @order.location
      return unless location && sales_day_posted?(location)

      ::Accounting::PostDailySalesJob.perform_now(location.id, business_date)
    end

    def sales_day_posted?(location)
      JournalEntry.unscoped.where(
        source_record_type: "Location", source_record_id: location.id,
        company_id: @order.company_id, date: business_date
      ).where("journal_entries.description LIKE ?", "%[daily_sales]%").exists?
    end

    def business_date
      # Not BusinessDay.for: on a manual-day branch that answers "today", whatever
      # the time given. Only orders from before business_date existed lack one.
      @business_date ||= @order.business_date ||
                         (@order.created_at.in_time_zone -
                          BusinessDay.start_hour(location: @order.location).hours).to_date
    end
  end
end
