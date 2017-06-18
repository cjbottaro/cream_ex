defmodule Cream.Supervisor.Cluster do
  use Supervisor

  import Cream.Utils, only: [parse_server: 1]

  def start_link(options) do
    Supervisor.start_link(__MODULE__, options)
  end

  def init(options) do
    servers = options[:servers]

    # Make a map of server to Memcache.Connection name so that
    # Cluster.Worker process knows how to access the connections managed by
    # this supervisor.
    # Ex:
    #   %{
    #     "127.0.0.1:11211" => {:via, Registry, ...},
    #     "localhost:11211" => {:via, Registry, ...}
    #   }
    server_name_map = Enum.reduce servers, %{}, fn server, acc ->
      Map.put(acc, server, Cream.Registry.new_connection)
    end

    # Each Memcache.Connection gets supervised.
    specs = Enum.map server_name_map, fn {server, name} ->
      {host, port} = parse_server(server)

      worker(
        Memcache.Connection,
        [[hostname: host, port: port, coder: Memcache.Coder.JSON], [name: name]],
        id: {Memcache.Connection, server}
      )
    end

    # Cluster.Worker gets supervised and passed the connection name map.
    specs = [
      worker(Cream.Cluster.Worker, [server_name_map]) | specs
    ]

    supervise(specs, strategy: :one_for_one)
  end

end
