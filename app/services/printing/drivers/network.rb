# frozen_string_literal: true

require "socket"

module Printing
  module Drivers
    class Network
      class Error < StandardError; end

      DEFAULT_PORT = 9100
      TIMEOUT = 5
      CHECK_TIMEOUT = 3

      def self.print!(host:, data:, port: DEFAULT_PORT, timeout: TIMEOUT)
        socket = connect!(host, port, timeout: timeout)
        socket.write(data)
        socket.close
      rescue StandardError => e
        raise Error, friendly_error_message(e, host: host, port: port)
      end

      def self.check_connection(host:, port: DEFAULT_PORT, timeout: CHECK_TIMEOUT)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        socket = connect!(host, port, timeout: timeout)
        socket.close
        latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

        { ok: true, latency_ms: latency_ms }
      rescue StandardError => e
        {
          ok: false,
          error_class: e.class.name,
          error: friendly_error_message(e, host: host, port: port)
        }
      end

      def self.connect!(host, port, timeout:)
        Socket.tcp(host.to_s.strip, port, connect_timeout: timeout)
      end
      private_class_method :connect!

      def self.friendly_error_message(error, host:, port:)
        case error
        when Errno::ETIMEDOUT
          I18n.t("printing.errors.timeout", host: host, port: port)
        when Errno::ECONNREFUSED
          I18n.t("printing.errors.conn_refused", host: host, port: port)
        when Errno::EHOSTUNREACH, Errno::ENETUNREACH
          I18n.t("printing.errors.no_route", host: host, port: port)
        else
          error.message
        end
      end
      private_class_method :friendly_error_message
    end
  end
end
