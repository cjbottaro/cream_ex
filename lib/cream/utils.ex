defmodule Cream.Utils do

  def normalize_host({host, port}), do: {host, normalize_port(port)}
  def normalize_host(host) when is_binary(host) do
    case String.split(host, ":", parts: 2) do
      [host, port | []] -> {host, normalize_port(port)}
      [host | []] -> {host, 11211}
    end
  end

  defp normalize_port(port) when is_binary(port), do: String.to_integer(port)
  defp normalize_port(port) when is_integer(port), do: port

  def normalize_key(key), do: "#{key}"
  def normalize_value(value), do: value

end
