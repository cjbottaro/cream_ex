defmodule Cream.Connection do
  @moduledoc """
  Basic connection to a single memcached server.

  You probably don't want this unless you're making some low level Memcached
  client. See `Cream.Client` instead.

  ## Global configuration

  You can globally configure _all connections_ via `Config`.
  ```
  import Config

  config :cream, Cream.Connection, server: "foo.bar.com:11211"
  ```

  Now every single connection will use `"foo.bar.com:11211"` for `:server`
  unless overwritten by an argument passed to `start_link/1` or `child_spec/1`.

  > **IMPORTANT!** This will affect connections made by `Cream.Client`.

  ## Reconnecting

  `Cream.Connection` uses the awesome `Connection` behaviour and also "active"
  sockets, which means a few things...
  1. `start_link/1` will typically always succeed.
  1. Disconnections are detected immediately.
  1. (Re)connections are retried indefinitely.

  While a connection is in a disconnected state, any operations on the
  connection will result in `{:error, :not_connected}`.

  ## Value serialization

  Coders serialize and deserialize values. They are also responsible for setting
  flags on values.

  See `Cream.Coder` for more info.
  """

  use Connection
  require Logger
  alias Cream.{Protocol, Coder}

  @typedoc """
  A connection.
  """
  @type t :: GenServer.server()

  @typedoc """
  Item used with `set/3`.

  An item is a key/value tuple or a key/value/opts tuple.

  ```
  {"foo", "bar"}
  {"foo", "bar", ttl: 60}
  {"foo", "bar", cas: 123}
  {"foo", "bar", ttl: 60, cas: 123}
  ```
  """
  @type item :: {binary, term} | {binary, term, Keyword.t}

  @typedoc """
  An error reason.
  """
  @type reason :: atom | binary | term

  @typedoc """
  Check and set value.
  """
  @type cas :: non_neg_integer()

  @defaults [
    server: "localhost:11211",
    coder: nil,
  ]

  @doc """
  Default config.

  ```
  #{inspect @defaults, pretty: true, width: 0}
  ```
  """
  def defaults, do: @defaults

  @doc """
  `Config` merged with `defaults/0`.

  ```
  import Config
  config :cream, Cream.Connection, coder: FooCoder

  iex(1)> Cream.Connection.config()
  #{inspect Keyword.merge(@defaults, coder: FooCoder), pretty: true, width: 0}
  ```
  """
  def config do
    config = Application.get_application(__MODULE__)
    |> Application.get_env(__MODULE__, [])

    Keyword.merge(@defaults, config)
  end

  @doc """
  Start connection.

  The given `config` will be merged over `config/0`.

  See `defaults/0` for config options.

  Note that this will typically _always_ return `{:ok conn}`, even if the actual
  TCP connection failed. If that is the case, subsequent uses of the connection
  will return `{:error, :not_connected}`.

  ```
  {:ok, conn} = #{inspect __MODULE__}.start_link()

  {:ok, conn} = #{inspect __MODULE__}.start_link(server: "memcache.foo.com:11211")
  ```
  """
  @spec start_link(Keyword.t) :: {:ok, t} | {:error, reason}
  def start_link(config \\ []) do
    config = Keyword.merge(config(), config)
    Connection.start_link(__MODULE__, config)
  end

  @doc """
  Clear all keys.

  ```
  # Flush immediately
  iex(1)> #{inspect __MODULE__}.flush(conn)
  :ok

  # Flush after 60 seconds
  iex(1)> #{inspect __MODULE__}.flush(conn, ttl: 60)
  :ok
  ```
  """
  @spec flush(t, Keyword.t) :: :ok | {:error, reason}
  def flush(conn, opts \\ []) do
    Connection.call(conn, {:flush, opts})
  end

  @doc """
  Set a single item.

  ## Options

  * `ttl` (`integer | nil`) - Apply time to live (expiry) to the item. Default
    `nil`.
  * `return_cas` (`boolean`) - Return cas value in result. Default `false`.
  * `coder` (`atom | nil`) - Use a `Cream.Coder` on value. Overrides the config
    used by `start_link/1`. Default `nil`.

  If `ttl` is set explicitly on the item, that will take precedence over the
  `ttl` specified in `opts`.

  ## Examples

  ```
  # Basic set
  iex(1)> set(conn, {"foo", "bar"})
  :ok

  # Use ttl on item.
  iex(1)> set(conn, {"foo", "bar", ttl: 60})
  :ok

  # Use ttl from opts.
  iex(1)> set(conn, {"foo", "bar"}, ttl: 60)
  :ok

  # Return cas value.
  iex(1)> set(conn, {"foo", "bar"}, return_cas: true)
  {:ok, 123}

  # Set using bad cas value results in error.
  iex(1)> set(conn, {"foo", "bar", cas: 124})
  {:error, :exists}

  # Set using cas value and return new cas value.
  iex(1)> set(conn, {"foo", "bar", cas: 123}, return_cas: true)
  {:ok, 124}

  # Set using cas.
  iex(1)> set(conn, {"foo", "bar", cas: 124})
  :ok
  ```
  """
  @spec set(t, item, Keyword.t) :: :ok | {:ok, cas} | {:error, reason}
  def set(conn, item, opts \\ []) do
    item = Cream.Utils.normalize_item(item)
    Connection.call(conn, {:set, item, opts})
  end

  @doc """
  Get a single item.

  ## Options

  * `verbose` (boolean, default false) Missing value will return `{:error, :not_found}`.
  * `cas` (boolean, default false) Return cas value in result.

  ## Examples

  ```
  iex(1)> get(conn, "foo")
  {:ok, nil}

  iex(1)> get(conn, "foo", verbose: true)
  {:error, :not_found}

  iex(1)> get(conn, "name")
  {:ok, "Callie"}

  iex(1)> get(conn, "name", return_cas: true)
  {:ok, "Callie", 123}
  ```
  """
  @spec get(t, binary, Keyword.t) :: {:ok, term} | {:ok, term, cas} | {:error, reason}
  def get(conn, key, options \\ []) do
    case Connection.call(conn, {:get, key, options}) do
      {:error, :not_found} = result -> if options[:verbose] do
        result
      else
        {:ok, nil}
      end

      result -> result
    end
  end

  @doc """
  Send a noop command to server.

  You can use this to see if you are connected to the server.
  ```
  iex(1)> noop(conn)
  :ok

  iex(1)> noop(conn)
  {:error, :not_connected}
  ```
  """
  @spec noop(t) :: :ok | {:error, reason}
  def noop(conn) do
    case Connection.call(conn, :noop) do
      {:ok, packet} -> case packet do
        %{status: :ok} -> :ok
        %{status: reason} -> {:error, reason}
      end
      error -> error
    end
  end

  def init(config) do
    state = %{
      config: config,
      socket: nil,
      coder: nil,
      errors: 0,
    }

    {:connect, :init, state}
  end

  def connect(context, state) do
    %{config: config} = state

    server = config[:server]
    [host, port] = String.split(server, ":")
    host = String.to_charlist(host)
    port = String.to_integer(port)

    start = System.monotonic_time(:microsecond)

    case :gen_tcp.connect(host, port, [:binary, active: true]) do
      {:ok, socket} ->
        :telemetry.execute(
          [:cream, :connection, :connect],
          %{usec: System.monotonic_time(:microsecond) - start},
          %{context: context, server: server}
        )
        {:ok, %{state | socket: socket, errors: 0}}

      {:error, reason} ->
        errors = state.errors + 1
        :telemetry.execute(
          [:cream, :connection, :error],
          %{usec: System.monotonic_time(:microsecond) - start},
          %{context: context, reason: reason, server: server, count: errors}
        )
        {:backoff, 1000, %{state | errors: errors}}
    end
  end

  def disconnect(reason, state) do
    %{config: config, socket: socket} = state

    :telemetry.execute(
      [:cream, :connection, :disconnect],
      %{},
      %{reason: reason, server: config[:server]}
    )

    :ok = :gen_tcp.close(socket)

    {:connect, reason, %{state | socket: nil}}
  end

  def handle_call(_command, _from, state) when is_nil(state.socket) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:flush, options}, _from, state) do
    %{socket: socket} = state

    with :ok <- :inet.setopts(socket, active: false),
      :ok <- :gen_tcp.send(socket, Protocol.flush(options)),
      {:ok, packet} <- Protocol.recv_packet(socket),
      :ok <- :inet.setopts(socket, active: true)
    do
      case packet.status do
        :ok -> {:reply, :ok, state}
        error -> {:reply, {:error, error}, state}
      end
    else
      {:error, reason} -> {:disconnect, reason, state}
    end
  end

  def handle_call({:set, item, opts}, _from, state) do
    %{socket: socket} = state

    {key, value, ttl, cas} = item
    coder = opts[:coder] || state.coder

    with {:ok, value, flags} <- encode(value, coder),
      packet = Protocol.set({key, value, ttl, cas, flags}),
      :ok <- :inet.setopts(socket, active: false),
      :ok <- :gen_tcp.send(socket, packet),
      {:ok, packet} <- Protocol.recv_packet(socket),
      :ok <- :inet.setopts(socket, active: true)
    do
      case packet.status do
        :ok -> if opts[:return_cas] do
          {:reply, {:ok, packet.cas}, state}
        else
          {:reply, :ok, state}
        end
        error -> {:reply, {:error, error}, state}
      end
    else
      {:error, reason} -> {:disconnect, reason, state}
    end
  end

  def handle_call({:get, key, opts}, _from, state) do
    %{socket: socket} = state

    packet = Protocol.get(key)
    coder = opts[:coder] || state.coder

    with :ok <- :inet.setopts(socket, active: false),
      :ok <- :gen_tcp.send(socket, packet),
      {:ok, packet} <- Protocol.recv_packet(socket),
      :ok <- :inet.setopts(socket, active: true)
    do
      case packet.status do
        :ok ->
          with {:ok, value} <- decode(packet.value, packet.extras.flags, coder) do
            if opts[:return_cas] do
              {:reply, {:ok, value, packet.cas}, state}
            else
              {:reply, {:ok, value}, state}
            end
          else
            {:error, reason} -> {:reply, {:error, reason}, state}
          end

        reason -> {:reply, {:error, reason}, state}
      end
    else
      {:error, reason} -> {:disconnect, reason, state}
    end
  end

  def handle_call(:noop, _from, state) do
    %{socket: socket} = state

    with :ok <- :inet.setopts(socket, active: false),
      :ok <- :gen_tcp.send(socket, Protocol.noop()),
      {:ok, packet} <- Protocol.recv_packet(socket),
      :ok <- :inet.setopts(socket, active: true)
    do
      {:reply, {:ok, packet}, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:disconnect, :tcp_closed, state}
  end

  defp encode(value, nil), do: {:ok, value, 0}
  defp encode(value, coder) do
    Coder.encode(coder, value, 0)
  end

  defp decode(value, _flags, nil), do: {:ok, value}
  defp decode(value, flags, coders) when is_list(coders) do
    Enum.reverse(coders) |> Coder.decode(value, flags)
  end
  defp decode(value, flags, coder) do
    Coder.decode(coder, value, flags)
  end

end
