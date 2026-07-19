# frozen_string_literal: true

module Printing
  module Drivers
    # Sends ESC/POS bytes to the local print agent process running on the
    # restaurant machine. Supports both network printers (host:port) and
    # USB printers (Windows device name, e.g. "USB001").
    module PrintAgent
      Error = Class.new(StandardError)

      TIMEOUT = 10 # seconds

      module_function

      def print_network!(host:, port:, data:)
        post_to_agent(
          connection: "network",
          host: host,
          port: port,
          data_base64: Base64.strict_encode64(data)
        )
      end

      def print_usb!(device:, data:)
        post_to_agent(
          connection: "usb",
          device: device,
          data_base64: Base64.strict_encode64(data)
        )
      end

      private

      def post_to_agent(body)
        uri = URI.parse("#{Config.agent_url}/print")
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT

        request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
        request["X-Print-Agent-Token"] = Config.agent_token if Config.agent_token.present?
        request.body = body.to_json

        response = http.request(request)
        result = JSON.parse(response.body) rescue {}

        unless response.is_a?(Net::HTTPSuccess) && result["ok"]
          raise Error, result["error"] || "Print agent returned HTTP #{response.code}"
        end

        result
      end
    end
  end
end
