# frozen_string_literal: true

require "socket"

module Printing
  module Drivers
    class Network
      class Error < StandardError; end

      DEFAULT_PORT = 9100
      TIMEOUT = 5

      def self.print!(host:, data:, port: DEFAULT_PORT, timeout: TIMEOUT)
        socket = Socket.tcp(host, port, connect_timeout: timeout)
        socket.write(data)
        socket.close
      rescue StandardError => e
        raise Error, e.message
      end
    end
  end
end
