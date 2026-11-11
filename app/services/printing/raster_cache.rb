# frozen_string_literal: true

module Printing
  # Keeps the printer images ImageMagick draws for a receipt, so the same picture is
  # never drawn twice in the same process.
  #
  # Each image costs a new ImageMagick process (about 0.3s on a Heroku dyno), and a
  # receipt needed ~16 of them, so the cashier waited ~4.5s for the bytes. Most of
  # those images repeat on every receipt: the logo, the shop name, the table header,
  # the separators, the footer and the usual menu lines.
  #
  # Every key holds every input that changes the picture (the full ImageMagick
  # command, or the uploaded logo's storage key), so a stale image cannot come back:
  # a changed setting is a new key. Only successful renders are kept.
  #
  # Process-local on purpose: no network hop, and each Puma worker or Sidekiq process
  # warms up after its first receipt. Bounded: the least recently used image goes
  # first. A row image is ~4KB, so the cap is a few MB per process.
  module RasterCache
    MAX_ENTRIES = 2_000

    @store = {}
    @lock = Mutex.new
    @enabled = !Rails.env.test?

    class << self
      attr_accessor :enabled

      # Returns the cached value for key, or runs the block and keeps a non-nil result.
      # The block runs outside the lock: two threads may draw the same image once each,
      # which is harmless, and nobody waits on someone else's ImageMagick.
      def fetch(key)
        return yield unless enabled

        hit = @lock.synchronize do
          next unless @store.key?(key)

          value = @store.delete(key)
          @store[key] = value # most recently used goes to the back
        end
        return hit if hit

        value = yield
        return value if value.nil?

        @lock.synchronize do
          @store[key] = value.frozen? ? value : value.dup.freeze
          @store.shift while @store.size > MAX_ENTRIES
        end
        value
      end

      def key?(key)
        @lock.synchronize { @store.key?(key) }
      end

      def clear
        @lock.synchronize { @store.clear }
      end

      def size
        @lock.synchronize { @store.size }
      end
    end
  end
end
