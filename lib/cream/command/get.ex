defmodule Cream.Command.Get do
  use Cream.Command

  def get(pool, key) when is_atom(pool) or is_pid(pool) do
    Cream.ConnectionPool.with pool, fn cluster ->
      get(cluster, key)
    end
  end

  def get(c = %Cluster{}, key) when not is_list(key) do
    get(c, [key]) |> Map.values |> List.first
  end

  def get(c = %Cluster{}, keys) do
    keys = Enum.map(keys, &Cream.Utils.normalize_key/1)

    keys_by_server = Enum.group_by keys, fn(key) ->
      {:ok, server } = Cluster.server_for_key(c, key)
      server
    end

    Enum.reduce keys_by_server, %{}, fn {server, keys}, acc ->
      # Make the request.
      commands = Enum.map(keys, &({:GETKQ, [&1]})) # [{:GETKQ, ["foo"]}, {:GETKQ, ["bar"]}, ...]
      {:ok, responses} = Memcache.Connection.execute_quiet(server, commands)

      # Accumulate the results.
      Enum.reduce responses, acc, fn response, acc ->
        case response do
          {:ok, key, value} ->
            Map.put(acc, key, value)
          _ -> acc
        end
      end
    end
  end

end
