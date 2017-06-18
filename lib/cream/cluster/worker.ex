require Logger

defmodule Cream.Cluster.Worker do
  use GenServer

  alias Cream.Continuum

  def start_link(connection_map) do
    GenServer.start_link(__MODULE__, connection_map)
  end

  def init(connection_map) do
    Logger.debug "Starting: #{inspect connection_map}"

    continuum = connection_map
      |> Map.keys
      |> Continuum.new

    {:ok, %{continuum: continuum, connection_map: connection_map}}
  end

  def handle_call({:set, pairs}, _from, state) do

    pairs_by_conn = Enum.group_by pairs, fn {key, _value} ->
      find_conn(state, key)
    end

    reply = Enum.reduce pairs_by_conn, [], fn {conn, pairs}, acc ->

      commands = Enum.map(pairs, fn {key, value} -> {:SETQ, [key, value]} end)

      {:ok, responses} = Memcache.Connection.execute_quiet(conn, commands)

      Enum.zip(pairs, responses)
        |> Enum.reduce(acc, fn {pair, status}, acc ->
          {key, _value} = pair
          [{key, status} | acc]
        end)

    end

    {:reply, reply, state}
  end

  def handle_call({:get, keys}, _from, state) do
    keys_by_conn = Enum.group_by keys, fn key ->
      find_conn(state, key)
    end

    reply = Enum.reduce keys_by_conn, %{}, fn {conn, keys}, acc ->
      commands = Enum.map(keys, &({:GETKQ, [&1]})) # [{:GETKQ, ["foo"]}, {:GETKQ, ["bar"]}, ...]

      {:ok, responses} = Memcache.Connection.execute_quiet(conn, commands)

      Enum.reduce(responses, acc, fn response, acc ->
        case response do
          {:ok, key, value} -> Map.put(acc, key, value)
          {:ok, "Key not found"} -> acc
        end
      end)
    end

    {:reply, reply, state}
  end

  def handle_call({:flush, options}, _from, state) do
    ttl = Keyword.get(options, :ttl, 0)

    reply = Enum.map state.connection_map, fn {_server, conn} ->
      case Memcache.Connection.execute(conn, :FLUSH, [ttl]) do
        {:ok} -> :ok
        whatever -> whatever
      end
    end

    {:reply, reply, state}
  end

  defp find_conn(state, key) do
    {:ok, server} = Continuum.find(state.continuum, key)
    state.connection_map[server]
  end

end
