defmodule Cream.Cluster do
  @moduledoc false

  defstruct [:continuum, :servers, :connections]

  alias Cream.{Connection, Continuum}

  def new(config \\ []) do
    case Keyword.fetch!(config, :servers) do
      [server] ->
        config = Keyword.put(config, :server, server)
        {:ok, conn} = Connection.start_link(config)
        %__MODULE__{servers: [server], connections: {conn}}

      servers ->
        continuum = Continuum.new(servers)

        conns = Enum.map(servers, fn server ->
          config = Keyword.put(config, :server, server)
          {:ok, conn} = Connection.start_link(config)
          conn
        end)
        |> List.to_tuple()

        %__MODULE__{servers: servers, connections: conns, continuum: continuum}
    end
  end

  def set(cluster, item, opts \\ []) do
    key = elem(item, 0)
    find_conn(cluster, key)
    |> Cream.Connection.set(item, opts)
  end

  def get(cluster, key, opts \\ []) do
    find_conn(cluster, key)
    |> Cream.Connection.get(key, opts)
  end

  def flush(cluster, opts \\ []) do
    errors = cluster.servers
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {server, i}, acc ->
      conn = elem(cluster.connections, i)
      case Cream.Connection.flush(conn, opts) do
        :ok -> acc
        {:error, reason} -> Map.put(acc, server, reason)
      end
    end)

    if errors == %{} do
      :ok
    else
      {:errors, errors}
    end
  end

  def find_conn(%{continuum: nil, connections: {conn}}, _key), do: conn
  def find_conn(%{continuum: continuum, connections: conns}, key) do
    {:ok, server_id} = Continuum.find(continuum, key)
    elem(conns, server_id)
  end

end
