defmodule Cream.Utils do

  def parse_server(server) do
    [host, port | []] = server |> to_string |> String.split(":")
    {host, String.to_integer(port)}
  end

end
