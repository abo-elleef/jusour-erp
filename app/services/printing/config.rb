# frozen_string_literal: true

module Printing
  module Config
    ROUTING_SERVER = "server"
    ROUTING_CLIENT = "client"
    DEFAULT_AGENT_PORT = 9310

    module_function

    def routing
      Setting.get("print_routing", ROUTING_CLIENT)
    end

    def client_routing?
      routing == ROUTING_CLIENT
    end

    def server_routing?
      !client_routing?
    end

    def agent_port
      Setting.get_int("print_agent_port", DEFAULT_AGENT_PORT)
    end

    def agent_url
      "http://127.0.0.1:#{agent_port}"
    end

    def agent_token
      Setting.get("print_agent_token", "")
    end

    def print_encoding
      Setting.get("print_encoding", "auto")
    end

    def print_code_page
      Setting.get_int("print_code_page", 0)
    end

    # Optional override path to an Arabic TTF/TTC font for raster image printing.
    # Leave blank to auto-detect from CANDIDATE_FONTS list.
    def arabic_font_path
      Setting.get("arabic_font_path", "")
    end
  end
end
