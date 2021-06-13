defmodule Cream.Continuum do
  @moduledoc false

  @points_per_server 160 # Dalli says this is the default in libmemcached.

  def new(servers) do
    total_servers = length(servers)
    total_weight  = length(servers) # TODO implement weights

    Enum.reduce(servers, [], fn server, acc ->
      count = entry_count_for(server, 1, total_servers, total_weight)
      Enum.reduce 0..count-1, acc, fn i, acc ->
        hash = :crypto.hash(:sha, "#{server}:#{i}") |> Base.encode16
        {value, _} = hash |> String.slice(0, 8) |> Integer.parse(16)
        [{server, value} | acc]
      end
    end)
    |> Enum.sort_by(fn {_id, value} -> value end)
    |> List.to_tuple
  end

  def find(continuum, key, attempt \\ 0)
  def find(_, _, 20), do: {:error, "No server available"}
  def find(continuum, key, attempt) do

    # Calculate the key's hash. If we're on attempt zero, then we don't modify it.
    hkey = if attempt == 0 do
      :erlang.crc32(key)
    else
      :erlang.crc32("#{key}:#{attempt}")
    end

    i = binary_search(continuum, hkey)

    # Wrap i around if it's -1. Gross.
    i = if i == -1, do: tuple_size(continuum)-1, else: i

    # Get the server.
    {server_id, _} = elem(continuum, i)

    if alive?(server_id) do
      {:ok, server_id}
    else
      find(continuum, key, attempt + 1)
    end

  end

  defp entry_count_for(_server, weight, total_servers, total_weight) do
    trunc((total_servers * @points_per_server * weight) / total_weight)
  end

  defp binary_search(entries, value), do: binary_search(entries, value, 0, tuple_size(entries)-1)
  defp binary_search(_entries, _value, lower, upper) when lower > upper, do: upper
  defp binary_search(entries, value, lower, upper) do
    i = ((lower + upper) / 2) |> trunc
    { _, candidate_value } = elem(entries, i)
    cond do
      candidate_value == value -> i
      candidate_value > value -> binary_search(entries, value, lower, i-1)
      candidate_value < value -> binary_search(entries, value, i+1, upper)
    end
  end

  defp alive?(_), do: true

end
