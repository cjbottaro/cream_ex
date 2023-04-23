defmodule Cream.Client do
  @moduledoc """
  Pooled connections to a Memcached server or cluster.

  `NimblePool` is used for connection pooling (lazy by default).

  ## Quickstart

      {:ok, client} = Cream.Client.start_link()
      :ok = Cream.Client.set(client, {"foo", "bar"})
      {:ok, "bar"} = Cream.Client.get(client, "foo")

  ## Global configuration

  You can globally configure _all clients_ via `Config`.

  ```
  import Config

  config :cream, Cream.Client, servers: [
    "localhost:11211",
    "localhost:11212",
    "localhost:11213"
  ]
  ```

  Now _every_ client will use those servers unless overwritten by an argument
  passed to `start_link/1`.

  ## Using as a module

  You can `use Cream.Client` for a higher level of convenience.

  ```
  def MyClient do
    use Cream.Client, coder: Cream.Coder.Jason
  end
  ```

  Configure with `Config`...
  ```
  config :my_app, MyClient, servers: ["cache.myapp.com"]
  ```

  Start it directly...

  ```
  {:ok, _client} = MyClient.start_link()
  ```

  Or as a part of a supervision tree...

  ```
  children = [MyClient]
  Supervisor.start_link(children, strategy: :one_for_one)
  ```

  Config is merged in a sensible order...
  1. `use` args
  1. `c:config/0`
  1. `c:start_link/1` args

  See `c:config/0` for an example.
  """

  @defaults [
    pool_size: 5,
    lazy: true,
    servers: ["localhost:11211"],
    coder: nil,
    ttl: nil
  ]

  @typedoc """
  Configuration options.

  * `pool_size` - How big the connection pool is.
  * `lazy` - If the connection pool is lazily loaded.
  * `servers` - What memcached servers to connect to.
  * `coder` - What `Cream.Coder` to use.
  * `ttl` - Default time to live (expiry) in seconds to use with `set/3`.

  Defaults are:
  ```
  #{inspect @defaults, pretty: true, width: 0}
  ```
  """
  @type config :: [
    {:pool_size, non_neg_integer},
    {:lazy, boolean},
    {:servers, [binary]},
    {:coder, module | nil},
    {:ttl, non_neg_integer | nil}
  ]

  @typedoc """
  A `Cream.Client`.
  """
  @type t :: GenServer.server()

  @typedoc """
  Error reason.
  """
  @type reason :: binary | atom | term

  alias Cream.{Cluster}

  @behaviour NimblePool

  @doc """
  Configuration as read from `Config`.

  ```
  import Config
  config :cream, Cream.Client, coder: FooCoder, ttl: 60

  iex(1)> Cream.Client.config()
  #{inspect Keyword.merge(@defaults, coder: FooCoder, ttl: 60), pretty: true, width: 0}
  ```
  """
  def config do
    config = Application.get_application(__MODULE__)
    |> Application.get_env(__MODULE__, [])

    Keyword.merge(@defaults, config)
  end

  @impl NimblePool
  def init_pool(config) do
    {:ok, config}
  end

  @impl NimblePool
  def init_worker(config) do
    {:ok, Cluster.new(config), config}
  end

  @impl NimblePool
  def handle_checkout(:checkout, _from, cluster, config) do
    {:ok, cluster, cluster, config}
  end

  @doc false
  def checkout(pool, f) do
    NimblePool.checkout!(pool, :checkout, fn _, client ->
      {f.(client), client}
    end)
  end

  @doc """
  Child specification for supervisors.

  `config` will be merged over `config/0`.
  """
  def child_spec(config \\ []) do
    {nimble_config, cream_config} =
      config()
      |> Keyword.merge(config)
      |> Keyword.split([:pool_size, :lazy, :name])

    nimble_config
    |> Keyword.put(:worker, {__MODULE__, cream_config})
    |> NimblePool.child_spec()
  end

  @doc """
  Start a client.

  `config` will be merged over `config/0`.

  Default options are:
  ```
  #{inspect @defaults, pretty: true, width: 0}
  ```
  """
  @spec start_link(config) :: {:ok, t} | {:error, reason}
  def start_link(config \\ []) do
    %{start: {m, f, a}} = child_spec(config)
    apply(m, f, a)
  end

  def get(client, key, opts \\ []) do
    checkout(client, &Cluster.get(&1, key, opts))
  end

  def set(client, item, opts \\ []) do
    checkout(client, &Cluster.set(&1, item, opts))
  end

  def fetch(client, key, opts \\ [], f) do
    checkout(client, &Cluster.fetch(&1, key, opts, f))
  end

  def delete(client, key, opts \\ []) do
    checkout(client, &Cluster.delete(&1, key, opts))
  end

  def flush(client, opts \\ []) do
    checkout(client, &Cluster.flush(&1, opts))
  end

  @doc """
  `Config` merged with `config/0` and `use` args.

  ```
  import Config

  config :cream, Cream.Client, servers: ["memcached:11211"]
  config :my_app, MyClient, coder: Cream.Coder.Jason

  defmodule MyClient do
    use Cream.Client, ttl: 60
  end

  iex(1)> Cream.Client.config()
  #{inspect Keyword.merge(@defaults,
    servers: ["memcached:11211"]),
    pretty: true,
    width: 0
  }

  iex(1)> MyClient.config()
  #{inspect Keyword.merge(@defaults,
    servers: ["memcached:11211"],
    coder: Cream.Coder.Jason,
    ttl: 60),
    pretty: true,
    width: 0
  }
  ```
  """
  @callback config :: Keyword.t

  @doc """
  Start a client.

  `config` is merged with `c:config/0`.
  """
  @callback start_link(config :: Keyword.t) :: {:ok, t} | {:error, reason}

  @doc """
  Child specification for supervisors.

  `config` is merged with `c:config/0`.
  """
  @callback child_spec(config :: Keyword.t) :: Supervisor.child_spec

  defmacro __using__(config \\ []) do
    quote do
      @config unquote(config)

      def config do
        base_config = Application.get_env(:cream, Cream.Client, [])
        this_config = Application.get_application(__MODULE__)
        |> Application.get_env(__MODULE__, [])

        @config
        |> Keyword.merge(base_config)
        |> Keyword.merge(this_config)
      end

      def child_spec(config \\ []) do
        Keyword.merge(config(), config)
        |> Keyword.put(:name, __MODULE__)
        |> Cream.Client.child_spec()
      end

      def start_link(config \\ []) do
        %{start: {m, f, a}} = child_spec(config)
        apply(m, f, a)
      end

      def get(key, opts \\ []) do
        Cream.Client.get(__MODULE__, key, opts)
      end

      def set(item, opts \\ []) do
        Cream.Client.set(__MODULE__, item, opts)
      end

      def fetch(key, opts \\ [], f) do
        Cream.Client.fetch(__MODULE__, key, opts, f)
      end

      def delete(key, opts \\ []) do
        Cream.Client.delete(__MODULE__, key, opts)
      end

      def flush(opts \\ []) do
        Cream.Client.flush(__MODULE__, opts)
      end

    end
  end

end