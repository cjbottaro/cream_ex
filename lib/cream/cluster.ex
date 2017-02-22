defmodule Cream.Cluster do
  defstruct [:continuum, :size]

  @points_per_server 160 # Dalli says this is the default in libmemcached.

  def new(options \\ []) do
    import Cream.Utils, only: [normalize_host: 1]

    hosts = Keyword.get(options, :hosts, ["localhost:11211"])

    servers = Enum.map hosts, fn host ->
      {host, port} = normalize_host(host)
      name = {:via, Registry, {Cream.Registry, UUID.uuid4()}}
      {:ok, _} = Cream.Supervisor.Connection.start_child([hostname: host, port: port], [name: name])
      %{ id: "#{host}:#{port}", name: name, weight: 1 }
    end

    %__MODULE__{
      size: length(servers),
      continuum: build_continuum(servers)
    }
  end

  def server_for_key(cluster, key, attempt \\ 0)
  def server_for_key(_, _, 20), do: {:error, "No server available"}
  def server_for_key(cluster, key, attempt) do

    # Calculate the key's hash. If we're on attempt zero, then we don't modify it.
    hkey = if attempt == 0 do
      :erlang.crc32(key)
    else
      :erlang.crc32("#{key}:#{attempt}")
    end

    i = binary_search(cluster.continuum, hkey)

    # Wrap i around if it's -1. Gross.
    i = if i == -1, do: tuple_size(cluster.continuum)-1, else: i

    # Get the server.
    {server_id, _} = elem(cluster.continuum, i)

    if alive?(server_id) do
      {:ok, server_id}
    else
      server_for_key(cluster.continuum, key, attempt + 1)
    end

  end

  defp build_continuum(servers) do
    total_servers = length(servers)
    total_weight = Enum.reduce(servers, 0, fn(server, acc) -> acc + server.weight end) # TODO implement weights

    continuum = Enum.reduce servers, [], fn server, acc ->
      count = entry_count_for(server, total_servers, total_weight)
      Enum.reduce 0..count-1, acc, fn i, acc ->
        hash = :crypto.hash(:sha, "#{server.id}:#{i}") |> Base.encode16
        {value, _} = hash |> String.slice(0, 8) |> Integer.parse(16)
        [{server.name, value} | acc]
      end
    end

    Enum.sort_by(continuum, fn {_id, value} -> value end) |> List.to_tuple
  end

  defp entry_count_for(server, total_servers, total_weight) do
    trunc((total_servers * @points_per_server * server.weight) / total_weight)
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
