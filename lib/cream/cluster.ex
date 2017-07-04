defmodule Cream.Cluster do
  @moduledoc """
  Connect to a cluster of memcached servers (or a single server if you want).

  ```elixir
  {:ok, cluster} = Cream.Cluster.start_link(servers: ["host1:11211", "host2:11211"])
  Cream.Cluster.get(cluster, "foo")
  ```

  Using a module and Mix.Config is preferred...
  ```elixir
  # In config/*.exs

  use Mix.Config
  config :cream, servers: ["host1:11211", "host2:11211"]

  # Elsewhere

  defmodule MyCluster do
    use Cream.Cluster
  end

  {:ok, _} = MyCluster.start_link
  MyCluster.get("foo")
  ```
  """

  @doc """
  Connect to memcached server(s)

  ## Options

  * `:servers` - Servers to connect to. Defaults to `["localhost:11211"]`.
  * `:pool` - Worker pool size. Defaults to `10`.
  * `:name` - Like name argument for `GenServer.start_link/3`. No default.
  * `:memcachex` - Keyword list passed through to `Memcache.start_link/2`

  ## Example

  ```elixir
  {:ok, cluster} = Cream.Cluster.start_link(
    servers: ["host1:11211", "host2:11211"],
    name: MyCluster,
    memcachex: [ttl: 60, namespace: "foo"]
  )
  ```
  """
  def start_link(options \\ []) do
    import Cream.Config, only: [
      default_servers: 0,
      default_pool: 0
    ]

    options = options
      |> Keyword.put_new(:servers, default_servers())
      |> Keyword.put_new(:pool, default_pool())

    poolboy_config = [
      worker_module: Cream.Supervisor.Cluster,
      size: options[:pool],
      name: options[:name],
    ] |> Keyword.delete(:name, nil) # Remove :name if it's nil.

    :poolboy.start_link(poolboy_config, options)
  end

  defmacro __using__(config \\ nil) do
    quote location: :keep, bind_quoted: [config: config] do

      @name {:via, Registry, {Cream.Registry, __MODULE__}}
      @config config

      alias Cream.{Config, Cluster}

      def start_link(options \\ []) do
        config = case @config do
          [] -> nil
          config -> config
        end

        Config.get(config)
          |> Keyword.merge(options)
          |> Keyword.put(:name, @name)
          |> Cluster.start_link
      end

      def set(key, value), do: Cluster.set(@name, key, value)
      def set(pairs), do: Cluster.set(@name, pairs)
      def get(keys), do: Cluster.get(@name, keys)
      def fetch(keys, options \\ [], func), do: Cluster.fetch(@name, keys, options, func)
      def delete(keys, options \\ []), do: Cluster.delete(@name, keys, options)
      def with_conn(keys, func), do: Cluster.with_conn(@name, keys, func)
      def flush(options \\ []), do: Cluster.flush(@name, options)

    end
  end

  def set(cluster, key_value, options \\ [])

  def set(cluster, key_value, options) when is_tuple(key_value) do
    set(cluster, [key_value], options) |> List.first
  end

  def set(cluster, keys_values, options) do
    with_worker cluster, fn worker ->
      GenServer.call(worker, {:set, keys_values})
    end
  end

  def get(cluster, key) when not is_list(key) do
    get(cluster, [key]) |> Map.values |> List.first
  end

  def get(cluster, keys, options \\ []) do
    with_worker cluster, fn worker ->
      GenServer.call(worker, {:get, keys})
    end
  end

  def fetch(cluster, key, options \\ [], func)

  def fetch(cluster, key, options, func) when not is_list(key) do
    case get(cluster, [key], options) do
      %{^key => value} ->
        value
      %{} ->
        value = func.()
        set(cluster, {key, value})
        value
    end
  end

  def fetch(cluster, keys, options, func) do
    hits = get(cluster, keys, options)
    missing_keys = Enum.reject(keys, &Map.has_key?(hits, &1))
    missing_hits = generate_missing(missing_keys, options, func)
    set(cluster, missing_hits, options)
    Map.merge(hits, missing_hits)
  end

  def delete(cluster, keys, options \\ [])

  def delete(cluster, keys, options) when is_list(keys) do
    with_worker cluster, fn worker ->
      GenServer.call(worker, {:delete, keys})
    end
  end

  def delete(cluster, key, options) when is_binary(key) do
    delete(cluster, [key], options)
  end

  def with_conn(cluster, keys, func) do
    with_worker cluster, fn worker ->
      GenServer.call(worker, {:with_conn, keys, func})
    end
  end

  def flush(cluster, options \\ []) do
    with_worker cluster, fn worker ->
      GenServer.call(worker, {:flush, options})
    end
  end

  defp generate_missing([], _options, _func), do: %{}
  defp generate_missing(keys, options, func) do
    values = func.(keys)
    cond do
      is_map(values) -> values
      is_list(values) -> Enum.zip(keys, values) |> Enum.into(%{})
    end
  end

  defp with_worker(cluster, func) do
    :poolboy.transaction cluster, fn supervisor ->
      supervisor
        |> Supervisor.which_children
        |> Enum.find(& elem(&1, 0) == Cream.Cluster.Worker )
        |> elem(1)
        |> func.()
    end
  end

end
