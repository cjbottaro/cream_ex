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

  @type t :: GenServer.server
  @type key :: String.t
  @type keys :: [key]
  @type value :: String.t | [value] | %{required(String.t) => value}
  @type keys_and_values :: [{key, value}] | %{required(key) => value}
  @type reason :: String.t
  @type memcache_connection :: GenServer.server

  @doc """
  Connect to memcached server(s)

  ## Options

  * `:servers` - Servers to connect to. Defaults to `["localhost:11211"]`.
  * `:pool` - Worker pool size. Defaults to `10`.
  * `:name` - Like name argument for `GenServer.start_link/3`. No default.
              Ignored if using module based cluster.
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
  @spec start_link(Keyword.t) :: t
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

      def set(arg1, arg2 \\ nil, arg3 \\ nil), do: Cluster.set(@name, arg1, arg2, arg3)
      def get(key_or_keys, options \\ []), do: Cluster.get(@name, key_or_keys, options)
      def delete(key_or_keys, options \\ []), do: Cluster.delete(@name, key_or_keys, options)
      def fetch(key_or_keys, options \\ [], func), do: Cluster.fetch(@name, key_or_keys, options, func)
      def with_conn(key_or_keys, func), do: Cluster.with_conn(@name, key_or_keys, func)
      def flush(options \\ []), do: Cluster.flush(@name, options)

    end
  end

  @doc """
  Set one or more keys.

  ## Single key

  `set(cluster, key, value, options \\\\ [])`

  `set(cluster, {key, value}, options \\\\ [])`

  ## Multiple keys

  `set(cluster, keys_and_values, options \\\\ [])`

  ## Examples
  ```
  # Single
  set("foo", "bar")
  set("foo", "bar", ttl: 60)
  set({"foo", "bar"})
  set({"foo", "bar"}, ttl: 60)

  # Multiple
  set(%{"one" => "one", "two" => "two"})
  set(%{"one" => "one", "two" => "two"}, ttl: 60)
  set([{"one", "one"}, {"two", "two"}])
  set([{"one", "one"}, {"two", "two"}], ttl: 60)
  ```
  """
  @spec set(t, key, value, Keyword.t) :: :ok | {:error, reason}
  @spec set(t, {key, value}, Keyword.t, nil) :: :ok | {:error, reason}
  @spec set(t, keys_and_values, Keyword.t, nil) :: %{required(key) => :ok | {:error, reason}}
  def set(cluster, arg1, arg2 \\ nil, arg3 \\ nil)

  def set(cluster, key_value, nil, nil) when is_tuple(key_value) do
    {key, value} = key_value
    set(cluster, key, value, nil)
  end

  def set(cluster, keys_and_values, nil, nil) do
    set(cluster, keys_and_values, [], nil)
  end

  def set(cluster, key, value, nil) when is_binary(key) do
    set(cluster, key, value, [])
  end

  def set(cluster, key_value, options, nil) when is_tuple(key_value) do
    {key, value} = key_value
    set(cluster, key, value, options)
  end

  def set(cluster, keys_and_values, options, nil) do
    with_worker cluster, fn worker ->
      GenServer.call(worker, {:set, keys_and_values, options})
    end
  end

  def set(cluster, key, value, options) when is_binary(key) do
    case set(cluster, [{key, value}], options) do
      %{ ^key => value } -> value
    end
  end

  @doc """
  Get one or more keys.

  ## Examples
  ```
  "bar" = get(pid, "foo")
  %{"foo" => "bar", "one" => "one"} = get(pid, ["foo", "bar"])
  ```
  """
  @spec get(t, key, Keyword.t) :: value
  @spec get(t, keys, Keyword.t) :: keys_and_values
  def get(cluster, key_or_keys, options \\ [])

  def get(cluster, key, options) when is_binary(key) do
    case get(cluster, [key], options) do
      %{ ^key => value } -> value
      _ -> nil
    end
  end

  def get(cluster, keys, options) do
    with_worker cluster, fn worker ->
      GenServer.call(worker, {:get, keys, options})
    end
  end

  @doc """
  Fetch one or more keys.
  """
  @spec fetch(t, key, Keyword.t, (() -> value)) :: value
  @spec fetch(t, keys, Keyword.t, (keys -> [value] | keys_and_values)) :: keys_and_values
  def fetch(cluster, key_or_keys, options \\ [], func)

  def fetch(cluster, key, options, func) when is_binary(key) do
    case get(cluster, [key], options) do
      %{^key => value} ->
        value
      %{} ->
        value = func.()
        set(cluster, key, value, options)
        value
    end
  end

  def fetch(cluster, keys, options, func) when is_list(keys) do
    hits = get(cluster, keys, options)
    missing_keys = Enum.reject(keys, &Map.has_key?(hits, &1))
    missing_hits = generate_missing(missing_keys, func)
    set(cluster, missing_hits, options)
    Map.merge(hits, missing_hits)
  end

  @doc """
  Delete one or more keys.

  ## Examples
  ```
  delete("foo")
  delete(["foo", "one"])
  ```
  """
  @spec delete(t, key, Keyword.t) :: :ok | {:error, reason}
  @spec delete(t, keys, Keyword.t) :: %{required(key) => :ok | {:error, reason}}
  def delete(cluster, key_or_keys, options \\ [])

  def delete(cluster, keys, options) when is_list(keys) do
    with_worker cluster, fn worker ->
      GenServer.call(worker, {:delete, keys, options})
    end
  end

  def delete(cluster, key, options) when is_binary(key) do
    delete(cluster, [key], options)
  end

  @doc """
  Get `Memcache` connection(s) for one or more keys.

  `Memcachex` doesn't support clustering. Cream supports clustering, but doesn't
  support the full memcached API. This function lets you do both.

  The connection yielded to the function can be used with all of the `Memcache`
  and `Memcache.Connection` modules.

  ## Examples
  ```
  with_conn cluster, keys, fn conn, keys ->
    Memcache.multi_get(conn, keys)
  end
  ```
  """
  @spec with_conn(t, key, (memcache_connection -> any)) :: any
  @spec with_conn(t, keys, (memcache_connection, keys -> any)) :: [any]
  def with_conn(cluster, key_or_keys, func)

  def with_conn(cluster, key, func) when is_binary(key) do
    with_conn(cluster, [key], func) |> List.first
  end

  def with_conn(cluster, keys, func) when is_list(keys) do
    with_worker cluster, fn worker ->
      GenServer.call(worker, {:with_conn, keys, func})
    end
  end

  @doc """
  Flush all memcached servers in the cluster.
  """
  @spec flush(t, Keyword.t) :: [:ok | {:error, reason}]
  def flush(cluster, options \\ []) do
    with_worker cluster, fn worker ->
      GenServer.call(worker, {:flush, options})
    end
  end

  defp generate_missing([], _func), do: %{}
  defp generate_missing(keys, func) do
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
