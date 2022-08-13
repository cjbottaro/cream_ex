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
  alias Cream.{Protocol, Coder, Error, ConnectionError}

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
  will return `{:error, %Cream.ConnectionError{}}`.

      # Connect to localhost:11211

      iex> start_link()
      {:ok, conn}

      # Connect to a specific server

      iex> start_link(server: "memcache.foo.com:11211")
      {:ok, conn}

      # Connection error

      iex> start_link(server: "localhost:99899")
      {:ok, conn}

      iex> get(conn, "foo")
      {:error, %Cream.Error{reason: :econnrefused, server: "localhost:99899"}}

  """
  @spec start_link(Keyword.t) :: {:ok, t} | {:error, reason}
  def start_link(config \\ []) do
    config = Keyword.merge(config(), config)
    Connection.start_link(__MODULE__, config)
  end

  @doc """
  Clear all keys.

      # Flush immediately
      iex> #{inspect __MODULE__}.flush(conn)
      :ok

      # Flush after 60 seconds
      iex> #{inspect __MODULE__}.flush(conn, ttl: 60)
      :ok

  """
  @spec flush(t, Keyword.t) :: :ok | {:error, Error.t} | {:error, ConnectionError.t}
  def flush(conn, opts \\ []) do
    case Connection.call(conn, {:flush, opts}) do
      {:ok, packet} -> case packet.status do
        :ok -> :ok
        reason -> {:error, Error.exception(reason)}
      end
      %ConnectionError{} = conn_error -> {:error, conn_error}
    end
  end

  @doc """
  Delete a key.

      iex> delete(conn, "foo")
      :ok

      iex> delete(conn, "foo", verbose: true)
      {:error, %Cream.Error{reason: :not_found}}

  """
  @spec delete(t, binary, Keyword.t) :: :ok | {:error, Error.t} | {:error, ConnectionError.t}
  def delete(conn, key, opts \\ []) do
    case Connection.call(conn, {:delete, key}) do
      {:ok, %{status: :ok}} -> :ok
      {:ok, %{status: :not_found}} -> if opts[:verbose] do
        {:error, Error.exception(:not_found)}
      else
        :ok
      end
      {:error, %ConnectionError{} = conn_error} -> {:error, conn_error}
      {:error, reason} -> {:error, Error.exception(reason)}
    end
  end

  @doc """
  Set a single item.

  ## Options

  * `:cas` - `(boolean)` - Return cas value in result. Default `false`.
  * `:coder` - `(atom|nil)` - Use a `Cream.Coder` on value. Overrides the config
    used by `start_link/1`. Default `nil`.

  `:ttl` on the item is in seconds. See `t:item/0` for more info.

  ## Examples

      # Basic set
      iex> set(conn, {"foo", "bar"})
      :ok

      # Use ttl.
      iex> set(conn, {"foo", "bar", ttl: 60})
      :ok

      # Set using cas.
      iex> set(conn, {"foo", "bar", cas: 122})
      :ok

      # Return cas value.
      iex> set(conn, {"foo", "bar"}, cas: true)
      {:ok, 123}

      # Set using bad cas value results in error.
      iex> set(conn, {"foo", "bar", cas: 124})
      {:error, %Cream.Error{reason: :exists}}

      # Set using cas value and return new cas value.
      iex> set(conn, {"foo", "bar", cas: 123}, cas: true)
      {:ok, 124}

  """
  @spec set(t, item, Keyword.t) :: :ok | {:ok, cas} | {:error, Error.t} | {:error, ConnectionError.t}
  def set(conn, item, opts \\ []) do
    opts_coder = case opts[:coder] do
      false -> false
      coder -> List.wrap(coder)
    end

    with {:ok, item} <- Cream.Item.from_args(item),
      {:ok, conn_coder} <- Connection.call(conn, :get_encoder),
      {:ok, item} <- encode(item, opts_coder, conn_coder),
      {:ok, %{status: :ok} = packet} <- Connection.call(conn, {:set, item})
    do
      if opts[:cas] do
        {:ok, packet.cas}
      else
        :ok
      end
    else
      {:ok, %{status: status}} -> {:error, Error.exception(status)}
      {:error, %ConnectionError{} = conn_error} -> {:error, conn_error}
      {:error, reason} -> {:error, Error.exception(reason)}
    end
  end

  @doc """
  Get a single item.

  ## Options

  * `:verbose` - `(boolean)` - If `true`, missing keys will return an error. If
    `false`, missing keys will return `nil`. Default `false`.
  * `:cas` - `(boolean)` - Return cas value in result. Default `false`.

  ## Examples

      iex> get(conn, "foo")
      {:ok, nil}

      iex> get(conn, "foo", verbose: true)
      {:error, %Cream.Error{reason: :not_found}}

      iex> get(conn, "name")
      {:ok, "Callie"}

      iex> get(conn, "name", cas: true)
      {:ok, "Callie", 123}

  """
  @spec get(t, binary, Keyword.t) :: {:ok, term} | {:ok, term, cas} | {:error, Error.t} | {:error, ConnectionError.t}
  def get(conn, key, opts \\ []) do
    opts_coder = case opts[:coder] do
      false -> false
      coder -> List.wrap(coder) |> Enum.reverse()
    end

    with {:ok, %{status: :ok} = packet, conn_coder} <- Connection.call(conn, {:get, key}),
      {:ok, value} <- decode(packet, opts_coder, conn_coder)
    do
      if opts[:cas] do
        {:ok, value, packet.cas}
      else
        {:ok, value}
      end
    else
      {:ok, %{status: :not_found}, _coder} -> if opts[:verbose] do
        {:error, Error.exception(:not_found)}
      else
        {:ok, nil}
      end
      {:ok, %{status: reason}, _coder} -> {:error, Error.exception(reason)}
      {:error, %ConnectionError{} = conn_error} -> {:error, conn_error}
      {:error, reason} -> {:error, Error.exception(reason)}
    end
  end

  @doc """
  Get a key and set its value if it doesn't exist.

  If `key` doesn't exist, then `f` is used to generate its value and set it on the server.

      iex> :ok = flush(conn)
      iex> {:ok, nil} = get(conn, "foo")
      iex> {:ok, "bar"} = fetch(conn, "foo", fn -> "bar" end)
      iex> {:ok, "bar"} = get(conn, "foo")

  `set/3` options will be used if the key doesn't exist.

  `get/3` options will always be used.
  """
  @spec fetch(t, binary, Keyword.t, (-> term)) :: {:ok, term} | {:ok, term, cas} | {:error, Error.t} | {:error, ConnectionError.t}
  def fetch(conn, key, opts \\ [], f) do
    case get(conn, key, Keyword.put(opts, :verbose, true)) do
      {:ok, value} -> {:ok, value}
      {:ok, value, cas} -> {:ok, value, cas}
      {:error, %Error{reason: :not_found}} ->
        value = f.()
        case set(conn, {key, value}, opts) do
          :ok -> {:ok, value}
          {:ok, cas} -> {:ok, value, cas}
          error -> error
        end

      error -> error
    end
  end

  @doc """
  Send a noop command to server.

  You can use this to see if you are connected to the server.

      iex> noop(conn)
      :ok

      iex> noop(conn)
      {:error, %Cream.Error{reason: :econnrefused, server: "localhost:11211"}}

  """
  @spec noop(t) :: :ok | {:error, Error.t} | {:error, ConnectionError.t}
  def noop(conn) do
    case Connection.call(conn, :noop) do
      {:ok, packet} -> case packet do
        %{status: :ok} -> :ok
        %{status: reason} -> {:error, Error.exception(reason)}
      end
      {:error, %ConnectionError{} = conn_error} -> {:error, conn_error}
      {:error, reason} -> {:error, Error.exception(reason)}
    end
  end

  def init(config) do
    encoder = List.wrap(config[:coder])
    decoder = Enum.reverse(encoder)

    state = %{
      config: config,
      socket: nil,
      encoder: encoder,
      decoder: decoder,
      err_reason: nil,
      err_count: 0,
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
        {:ok, %{state | socket: socket, err_count: 0}}

      {:error, reason} ->
        count = state.err_count + 1
        :telemetry.execute(
          [:cream, :connection, :error],
          %{usec: System.monotonic_time(:microsecond) - start},
          %{context: context, reason: reason, server: server, count: count}
        )
        {:backoff, 1000, %{state | err_reason: reason, err_count: count}}
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

  def handle_call(:get_encoder, _from, state) do
    {:reply, {:ok, state.encoder}, state}
  end

  def handle_call(_command, _from, state) when is_nil(state.socket) do
    error = ConnectionError.exception(state.err_reason, state.config[:server])
    {:reply, {:error, error}, state}
  end

  def handle_call({:flush, options}, from, state) do
    %{socket: socket} = state

    with :ok <- :inet.setopts(socket, active: false),
      :ok <- :gen_tcp.send(socket, Protocol.flush(options)),
      {:ok, packet} <- Protocol.recv_packet(socket),
      :ok <- :inet.setopts(socket, active: true)
    do
      {:reply, {:ok, packet}, state}
    else
      {:error, reason} -> handle_conn_error(reason, from, state)
    end
  end

  def handle_call({:delete, key}, from, state) do
    %{socket: socket} = state

    with :ok <- :inet.setopts(socket, active: false),
      :ok <- :gen_tcp.send(socket, Protocol.delete(key)),
      {:ok, packet} <- Protocol.recv_packet(socket),
      :ok <- :inet.setopts(socket, active: true)
    do
      {:reply, {:ok, packet}, state}
    else
      {:error, reason} -> handle_conn_error(reason, from, state)
    end
  end

  def handle_call({:set, item}, from, state) do
    %{socket: socket} = state

    packet = Protocol.set(item)

    with :ok <- :inet.setopts(socket, active: false),
      :ok <- :gen_tcp.send(socket, packet),
      {:ok, packet} <- Protocol.recv_packet(socket),
      :ok <- :inet.setopts(socket, active: true)
    do
      {:reply, {:ok, packet}, state}
    else
      {:error, reason} -> handle_conn_error(reason, from, state)
    end
  end

  def handle_call({:get, key}, from, state) do
    %{socket: socket, decoder: decoder} = state

    packet = Protocol.get(key)

    with :ok <- :inet.setopts(socket, active: false),
      :ok <- :gen_tcp.send(socket, packet),
      {:ok, packet} <- Protocol.recv_packet(socket),
      :ok <- :inet.setopts(socket, active: true)
    do
      {:reply, {:ok, packet, decoder}, state}
    else
      {:error, reason} -> handle_conn_error(reason, from, state)
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

  defp handle_conn_error(reason, from, %{config: config} = state) do
    error = ConnectionError.exception(reason: reason, server: config[:server])
    :ok = GenServer.reply(from, {:error, error})
    {:disconnect, reason, state}
  end

  defp encode(%Cream.Item{} = item, opts_coder, conn_coder) do
    result = case {opts_coder, conn_coder} do
      {false, _} -> :noop
      {[], []} -> :noop
      {coder, _} when coder != [] -> Coder.encode(coder, item.value, item.flags)
      {_, coder} when coder != [] -> Coder.encode(coder, item.value, item.flags)
    end

    case result do
      :noop -> {:ok, item}
      {:ok, value, flags} -> {:ok, %{item | value: value, flags: flags}}
      error -> error
    end
  end

  defp decode(packet, opts_coder, conn_coder) do
    case {opts_coder, conn_coder} do
      {false, _} -> {:ok, packet.value}
      {[], []} -> {:ok, packet.value}
      {coder, _} when coder != [] -> Coder.decode(coder, packet.value, packet.extras.flags)
      {_, coder} when coder != [] -> Coder.decode(coder, packet.value, packet.extras.flags)
    end
  end

end
