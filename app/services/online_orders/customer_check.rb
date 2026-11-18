# frozen_string_literal: true

module OnlineOrders
  # "Who is this?" for a waiting self-order: what we know about the phone, so the
  # cashier can tell a regular from a new number or a likely fake before accepting.
  #
  # Everything here is read-only facts plus one label:
  #   blocked   — the customer is blocked from self-ordering
  #   caution   — something looks off (see #reasons); call before accepting
  #   new       — no completed order on this phone; call first
  #   returning — 1–2 completed orders, nothing off
  #   trusted   — TRUSTED_MIN_COMPLETED+ completed orders, nothing off
  class CustomerCheck
    TRUSTED_MIN_COMPLETED = 3
    # Voided after being sent to the kitchen this many times → caution.
    CAUTION_MIN_VOIDED = 2
    SHARED_DEVICE_WINDOW = 7.days
    LEVELS = %w[blocked caution new returning trusted].freeze

    attr_reader :request, :customer

    def initialize(request, now: Time.current)
      @request = request
      @now = now
      @customer = request.customer || FindOrCreateCustomer.lookup(request.phone)
    end

    def level
      @level ||=
        if customer&.blocked? then "blocked"
        elsif reasons.any? then "caution"
        elsif completed_count.zero? then "new"
        elsif completed_count < TRUSTED_MIN_COMPLETED then "returning"
        else "trusted"
        end
    end

    # Why the label is "caution", most serious first.
    def reasons
      @reasons ||= [].tap do |list|
        list << :earlier_rejections if requests_by_status["rejected"].to_i.positive?
        list << :shared_device if shared_device_phones.positive?
        list << :name_mismatch if name_mismatch?
        list << :voided_orders if voided_count >= CAUTION_MIN_VOIDED
      end
    end

    # The number a caution reason is about (rejections, other phones, voids).
    def reason_count(reason)
      case reason
      when :earlier_rejections then requests_by_status["rejected"].to_i
      when :shared_device then shared_device_phones
      when :voided_orders then voided_count
      else 0
      end
    end

    # --- orders on file ---------------------------------------------------------

    def completed_count = order_stats[:completed_count]
    def total_spent_cents = order_stats[:total_spent_cents]
    def voided_count = order_stats[:voided_count]

    def last_order
      return @last_order if defined?(@last_order)

      @last_order = customer && orders.completed.includes(:location).order(Arel.sql("COALESCE(orders.placed_at, orders.created_at) DESC")).first
    end

    # --- this phone's other self-orders -------------------------------------------

    # { "accepted" => 2, "rejected" => 1, "expired" => 0 } for earlier requests.
    def requests_by_status
      @requests_by_status ||= other_requests.where.not(status: "pending").group(:status).count
    end

    # { "no_answer" => 1, "suspicious" => 1 }
    def rejection_reasons
      @rejection_reasons ||= other_requests.where(status: "rejected").where.not(reject_reason: nil).group(:reject_reason).count
    end

    # Other phones that self-ordered from the same device (IP) lately — one person
    # cycling numbers is the usual fake-order pattern.
    def shared_device_phones
      @shared_device_phones ||=
        if request.ip.blank? then 0
        else
          OnlineOrderRequest.where(ip: request.ip, created_at: (@now - SHARED_DEVICE_WINDOW)..)
                            .where.not(phone: request.phone).distinct.count(:phone)
        end
    end

    # --- what they typed vs what we have -----------------------------------------

    def name_on_file
      customer&.name.to_s.strip.presence
    end

    def name_mismatch?
      return false if name_on_file.blank?

      saved = name_words(name_on_file)
      typed = name_words(request.customer_name)
      return false if saved.empty? || typed.empty?

      saved.none? { |a| typed.any? { |b| same_word?(a, b) } }
    end

    # :known — the delivery address matches one we have for this customer;
    # :new — a delivery to an address we've never seen; nil for pickup.
    def address_status
      return nil unless request.delivery? && request.address.present?
      return :new unless customer

      @address_status ||= known_addresses.include?(squish(request.address)) ? :known : :new
    end

    def standing_note
      customer&.standing_note.presence
    end

    private

    def orders
      Order.where(customer: customer)
    end

    def order_stats
      @order_stats ||=
        if customer.nil?
          { completed_count: 0, total_spent_cents: 0, voided_count: 0 }
        else
          completed = orders.completed
          {
            completed_count: completed.count,
            total_spent_cents: completed.sum(:total_cents),
            # Sent to the kitchen, then voided. Abandoned carts (never placed) don't count.
            voided_count: orders.where(status: "cancelled").where.not(placed_at: nil).count
          }
        end
    end

    def other_requests
      OnlineOrderRequest.where(phone: request.phone).where.not(id: request.id)
    end

    def known_addresses
      saved = customer.addresses.pluck(:address)
      delivered = orders.where.not(delivery_address: [nil, ""]).distinct.pluck(:delivery_address)
      (saved + delivered).map { |a| squish(a) }.to_set
    end

    def squish(text)
      text.to_s.squish.downcase
    end

    # "mohamed" / "mohammed", "ahmed" / "ahmad": one letter apart is the same name.
    def same_word?(a, b)
      return true if a == b
      return false if a.length < 4 || b.length < 4 || (a.length - b.length).abs > 1

      one_edit_apart?(a, b)
    end

    def one_edit_apart?(a, b)
      a, b = b, a if a.length > b.length
      i = 0
      i += 1 while i < a.length && a[i] == b[i]
      if a.length == b.length
        a[(i + 1)..] == b[(i + 1)..]
      else
        a[i..] == b[(i + 1)..]
      end
    end

    # Loose word set so "أحمد" and "احمد محمد" count as the same person.
    def name_words(name)
      name.to_s.downcase
          .gsub(/[ً-ْـ]/, "") # harakat + tatweel
          .tr("أإآٱ", "اااا").tr("ة", "ه").tr("ى", "ي")
          .split(/[^\p{L}\p{N}]+/).reject { |w| w.length < 2 }.uniq
    end
  end
end
