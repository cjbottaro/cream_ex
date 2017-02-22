defmodule Cream.Command.Set do
  use Cream.Command

  def set(pool, keys_and_values) when is_atom(pool) or is_pid(pool) do
    ConnectionPool.with pool, &( set(&1, keys_and_values) )
  end

  def set(c = %Cluster{}, key_and_value) when is_tuple(key_and_value) do
    set(c, [key_and_value]) |> Map.values |> List.first
  end

  def set(c = %Cluster{}, keys_and_values) do
    keys_and_values = Enum.map keys_and_values, fn {key, value} ->
      {Cream.Utils.normalize_key(key), Cream.Utils.normalize_value(value)}
    end

    by_server = Enum.group_by keys_and_values, fn {key, _value} ->
      {:ok, server } = Cluster.server_for_key(c, key)
      server
    end

    Enum.reduce by_server, %{}, fn {server, keys_and_values}, acc ->
      # [{:SETQ, ["foo"]}, {:SETQ, ["bar"]}, ...]
      commands = Enum.map keys_and_values, fn {key, value} ->
        {:SETQ, [key, value]}
      end

      # Make the request.
      {:ok, responses} = Memcache.Connection.execute_quiet(server, commands)

      Enum.reduce Enum.zip(keys_and_values, responses), acc, fn { {key, _value }, response }, acc ->
        case response do
          {:ok} -> Map.put(acc, key, :ok)
          _ -> Map.put(acc, key, response)
        end
      end
    end
  end

end
