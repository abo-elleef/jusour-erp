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

    def blocked_reason
      customer&.blocked_reason.presence
    end

    # Everything the card shows, frozen as plain JSON — saved on the request when
    # it comes in and when it is decided, so a later review sees what the cashier
    # saw, not today's numbers. Read back with Snapshot.
    def to_snapshot
      last = last_order
      {
        "at" => @now.iso8601,
        "level" => level,
        "reasons" => reasons.to_h { |r| [r.to_s, reason_count(r)] },
        "customer_id" => customer&.id,
        "customer_name" => customer&.display_name,
        "name_on_file" => name_on_file,
        "name_mismatch" => name_mismatch?,
        "address_status" => address_status&.to_s,
        "completed_count" => completed_count,
        "total_spent_cents" => total_spent_cents,
        "voided_count" => voided_count,
        "last_order" => last && {
          "id" => last.id, "order_number" => last.order_number, "total_cents" => last.total_cents,
          "at" => (last.placed_at || last.created_at).iso8601, "location_name" => last.location&.name
        },
        "requests_by_status" => requests_by_status,
        "rejection_reasons" => rejection_reasons,
        "shared_device_phones" => shared_device_phones,
        "standing_note" => standing_note,
        "blocked_reason" => blocked_reason
      }
    end

    # A saved check, answering the same questions as CustomerCheck so the
    # "Who is this?" partial renders it unchanged.
    class Snapshot
      LastOrder = Struct.new(:id, :order_number, :total_cents, :placed_at, :created_at, :location, keyword_init: true)
      NamedLocation = Struct.new(:name)

      attr_reader :request, :data

      def initialize(request, data)
        @request = request
        @data = data || {}
      end

      def taken_at = Time.zone.parse(data["at"].to_s)
      def level = data["level"]
      def reasons = data.fetch("reasons", {}).keys.map(&:to_sym)
      def reason_count(reason) = data.fetch("reasons", {})[reason.to_s].to_i
      def name_on_file = data["name_on_file"]
      def name_mismatch? = data["name_mismatch"] == true
      def address_status = data["address_status"]&.to_sym
      def completed_count = data["completed_count"].to_i
      def total_spent_cents = data["total_spent_cents"].to_i
      def voided_count = data["voided_count"].to_i
      def requests_by_status = data.fetch("requests_by_status", {})
      def rejection_reasons = data.fetch("rejection_reasons", {})
      def shared_device_phones = data["shared_device_phones"].to_i
      def standing_note = data["standing_note"]
      def blocked_reason = data["blocked_reason"]

      # The customer record as it is now (for the link); nil if there was none then.
      def customer
        return @customer if defined?(@customer)

        @customer = data["customer_id"] && Customer.find_by(id: data["customer_id"])
      end

      def last_order
        lo = data["last_order"]
        return nil if lo.blank?

        at = Time.zone.parse(lo["at"].to_s)
        LastOrder.new(id: lo["id"], order_number: lo["order_number"], total_cents: lo["total_cents"].to_i,
                      placed_at: at, created_at: at, location: lo["location_name"] && NamedLocation.new(lo["location_name"]))
      end
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
