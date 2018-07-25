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
  config :my_app, MyCluster,
    servers: ["host1:11211", "host2:11211"]

  # Elsewhere

  defmodule MyCluster do
    use Cream.Cluster, otp_app: :my_app
  end

  {:ok, _} = MyCluster.start_link
  MyCluster.get("foo")
  ```
  """

  import Cream.Instrumentation

  @typedoc """
  Type representing a `Cream.Cluster`.
  """
  @type t :: GenServer.server

  @typedoc """
  A memcached key.
  """
  @type key :: String.t

  @typedoc """
  A list of keys.
  """
  @type keys :: [key]

  @typedoc """
  A value to be stored in memcached.
  """
  @type value :: String.t | serializable

  @typedoc """
  A key value pair.
  """
  @type item :: {key, value}

  @typedoc """
  Multiple items as a map.
  """
  @type items_map :: %{required(key) => value}

  @typedoc """
  Multiple items as a list of tuples or a map.
  """
  @type items :: [item] | items_map

  @typedoc """
  Reason associated with an error.
  """
  @type reason :: String.t

  @typedoc """
  A `Memcache.Connection`.
  """
  @type memcache_connection :: GenServer.server

  @typedoc """
  Anything serializable (to JSON).
  """
  @type serializable :: list | map

  @typedoc """
  Configuration options.
  """
  @type config :: Keyword.t

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do

      @otp_app opts[:otp_app]

      def init(config), do: {:ok, config}
      defoverridable [init: 1]

      def start_link(config \\ []) do
        Cream.Cluster.start_link(__MODULE__, @otp_app, config)
      end

      def child_spec(config) do
        %{ id: __MODULE__, start: {__MODULE__, :start_link, [config]} }
      end

      def set(items, opts \\ []), do: Cream.Cluster.set(__MODULE__, items, opts)
      def get(key_or_keys, opts \\ []), do: Cream.Cluster.get(__MODULE__, key_or_keys, opts)
      def delete(key_or_keys), do: Cream.Cluster.delete(__MODULE__, key_or_keys)
      def fetch(key_or_keys, opts \\ [], func), do: Cream.Cluster.fetch(__MODULE__, key_or_keys, opts, func)
      def with_conn(key_or_keys, func), do: Cream.Cluster.with_conn(__MODULE__, key_or_keys, func)
      def flush(opts \\ []), do: Cream.Cluster.flush(__MODULE__, opts)
      def put(key, value, opts \\ []), do: Cream.Cluster.put(__MODULE__, key, value, opts)

    end
  end

  @doc """
  For dynamic / runtime configuration.

  Ex:
  ```elixir
  defmodule MyCluster do
    use Cream.Cluster, otp_app: :my_app

    def init(config) do
      servers = System.get_env("MEMCACHED_SERVERS") |> String.split(",")
      config = Keyword.put(config, :servers, servers)
      {:ok, config}
    end
  end
  ```
  """
  @callback init(config) :: {:ok, config} | {:error, reason}

  @doc """
  For easily putting into supervision tree.

  Ex:
  ```elixir
  Supervisor.start_link([MyCluster], opts)
  ```
  Or if you want to do runtime config here instead of the `c:init/1` callback for
  some reason:
  ```elixir
  Supervisor.start_link([{MyCluster, servers: servers}], opts)
  ```
  """
  @callback child_spec(config) :: Supervisor.child_spec

  @doc """
  See `set/3`.
  """
  @callback set(item_or_items :: item | items, opts :: Keyword.t) ::
    :ok | {:error, reason}
    | %{required(key) => :ok | {:error | reason}}

  @doc """
  See `put/4`.
  """
  @callback put(key, value, opts :: Keyword.t) :: :ok | {:error, reason}

  @doc """
  See `get/2`.
  """
  @callback get(key_or_keys :: key | keys) :: value | items

  @doc """
  See `fetch/4`.
  """
  @callback fetch(key_or_keys :: key | keys, f :: (() -> value) | (keys -> [value] | items)) :: value | items

  @doc """
  See `delete/2`.
  """
  @callback delete(key_or_keys :: key | keys) ::
    (:ok | {:error, reason})
    | [{key, :ok | {:error, reason}}]

  @doc """
  See `flush/2`.
  """
  @callback flush(opts :: Keyword.t) :: :ok | {:error, reason}

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
  @defaults [
    servers: ["localhost:11211"],
    pool: 5,
    log: :debug
  ]
  @spec start_link(Keyword.t) :: t
  def start_link(opts \\ []) do
    opts = @defaults
      |> Keyword.merge(opts)
      |> Keyword.update!(:servers, &Cream.Utils.normalize_servers/1)

    poolboy_config = [
      worker_module: Cream.Supervisor.Cluster,
      size: opts[:pool],
    ]

    poolboy_config = if opts[:name] do
      Keyword.put(poolboy_config, :name, {:local, opts[:name]})
    else
      poolboy_config
    end

    # This is so gross. There is no way to link or register a poolboy process,
    # so we gotta wrap it in a task which subscribes to instrumentation.

    parent = self()
    rand = :crypto.strong_rand_bytes(8)

    result = Task.start_link fn ->
      if log_level = opts[:log] do
        Instrumentation.subscribe "cream", fn tag, payload ->
          Logger.bare_log(log_level, "cream.#{tag} #{inspect(payload)}")
        end
      end

      {:ok, _pid} = :poolboy.start_link(poolboy_config, opts)
      send(parent, {:cream_ready, rand})
      :timer.sleep(:infinity)
    end

    receive do
      {:cream_ready, ^rand} -> result
    after
      5000 -> {:error, "startup timeout"}
    end

  end

  @doc false
  # This is for starting a module based cluster.
  def start_link(mod, otp_app, opts) do
    opts = Keyword.put(opts, :name, mod)
    config = Application.get_env(otp_app, mod)
    with {:ok, config} <- mod.init(config) do
      Keyword.merge(config, opts) |> start_link
    end
  end

  @doc ~S"""
  Set the value of a single key.

  This a convenience function for `set(cluster, {key, value}, opts)`.
  See `set/3`.

  It has a different name because the follow definitions conflict:
  ```elixir
  set(cluster, key, value, opts \\ [])
  set(cluster, item, opts \\ [])
  ```
  """
  @spec put(t, key, value, Keyword.t) :: :ok | {:error, reason}
  def put(cluster, key, value, opts \\ []) do
    set(cluster, {key, value}, opts)
  end

  @doc """
  Set one or more keys.

  Single key examples:
  ```elixir
  set(cluster, {key, value})
  set(cluster, {key, value}, ttl: 300)
  ```

  Multiple key examples:
  ```elixir
  set(cluster, [{k1, v1}, {k2, v2}])
  set(cluster, [{k1, v1}, {k2, v2}], ttl: 300)

  set(cluster, %{k1 => v1, k2 => v2})
  set(cluster, %{k1 => v1, k2 => v2}, ttl: 300)
  ```
  """
 @spec set(t, item, Keyword.t()) :: :ok | {:error, reason}
 @spec set(t, items, Keyword.t()) :: %{required(key) => :ok | {:error, reason}}
 def set(cluster, item_or_items, opts \\ [])

  def set(cluster, items, opts) when is_list(items) or is_map(items) do
    with_worker cluster, fn worker ->
      instrument "set", [items: items], fn ->
        GenServer.call(worker, {:set, items, opts})
      end
    end
  end

  def set(cluster, item, opts) when is_tuple(item) do
    set(cluster, [item], opts) |> Map.values |> List.first
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
  @spec get(t, keys, Keyword.t) :: items_map
  def get(cluster, key_or_keys, opts \\ [])

  def get(cluster, key, opts) when is_binary(key) do
    case get(cluster, [key], opts) do
      %{ ^key => value } -> value
      _ -> nil
    end
  end

  def get(cluster, keys, opts) do
    with_worker cluster, fn worker ->
      instrument "get", [keys: keys], fn ->
        GenServer.call(worker, {:get, keys, opts})
      end
    end
  end

  @doc """
  Fetch one or more keys, falling back to a function if a key doesn't exist.

  `opts` is the same as for `set/3`.

  Ex:
  ```elixir
  fetch(cluster, "foo", fn -> "bar" end)

  fetch(cluster, ["foo", "bar"], fn missing_keys ->
    Enum.map(missing_keys, fn missing_key ->
      calc_value(missing_key)
    end)
  end)

  # In this example, we explicitly associate missing keys with values.
  fetch(cluster, ["foo", "bar"], fn missing_keys ->
    Enum.shuffle(missing_keys)
      |> Enum.map(fn missing_key ->
        {missing_key, calc_value(missing_key)}
      end)
  end)
  ```
  """
  @spec fetch(t, key, Keyword.t, (() -> value)) :: value
  @spec fetch(t, keys, Keyword.t, (keys -> [value] | items)) :: items
  def fetch(cluster, key_or_keys, opts \\ [], func)

  def fetch(cluster, key, opts, func) when is_binary(key) do
    instrument "fetch", [key: key], fn ->
      case get(cluster, [key], opts) do
        %{^key => value} ->
          {value, :hit}
        %{} ->
          value = func.()
          set(cluster, {key, value}, opts)
          {value, :miss}
      end
    end
  end

  def fetch(cluster, keys, opts, func) when is_list(keys) do
    instrument "fetch", [keys: keys], fn ->
      hits = get(cluster, keys, opts)
      missing_keys = Enum.reject(keys, &Map.has_key?(hits, &1))
      missing_hits = generate_missing(missing_keys, func)
      set(cluster, missing_hits, opts)
      results = Map.merge(hits, missing_hits)
      {results, missing_keys}
    end
  end

  @doc """
  Delete one or more keys.

  ## Examples
  ```
  delete("foo")
  delete(["foo", "one"])
  ```
  """
  @spec delete(t, key) :: :ok | {:error, reason}
  @spec delete(t, keys) :: %{required(key) => :ok | {:error, reason}}
  def delete(cluster, key_or_keys)

  def delete(cluster, keys) when is_list(keys) do
    with_worker cluster, fn worker ->
      instrument "delete", [keys: keys], fn ->
        GenServer.call(worker, {:delete, keys})
      end
    end
  end

  def delete(cluster, key) when is_binary(key) do
    delete(cluster, [key]) |> Map.values |> List.first
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
  def flush(cluster, opts \\ []) do
    with_worker cluster, fn worker ->
      instrument "flush", fn ->
        GenServer.call(worker, {:flush, opts})
      end
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
