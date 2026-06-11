# frozen_string_literal: true

module PrintingHelper
  def print_agent_config_json
    {
      url: Printing::Config.agent_url,
      token: Printing::Config.agent_token,
      client_routing: Printing::Config.client_routing?,
      port: Printing::Config.agent_port
    }.to_json
  end
end
