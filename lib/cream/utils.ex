defmodule Cream.Utils do
  @moduledoc false

  def normalize_servers(servers) do
    List.wrap(servers) |> Enum.map(fn server ->
      case to_string(server) |> String.split(":") do
        [host | []] -> "#{host}:11211"
        [host, port | []] -> "#{host}:#{port}"
      end
    end)
  end

  def parse_server(server) do
    [host, port | []] = server |> to_string |> String.split(":")
    {host, String.to_integer(port)}
  end

end
