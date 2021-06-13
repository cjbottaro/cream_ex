defmodule Cream.Connection do
  use Connection
  require Logger
  alias Cream.{Protocol}

  @type t :: GenServer.server()
  @type cas :: non_neg_integer()
  @type reason :: atom | binary | term
  @type get_result :: {:ok, term} | {:ok, {term, cas}} | {:error, reason}

  @defaults [
    server: "localhost:11211"
  ]

  def start_link(config \\ []) do
    mix_config = Application.get_application(__MODULE__)
    |> Application.get_env(__MODULE__, [])

    config = Keyword.merge(@defaults, mix_config)
    |> Keyword.merge(config)

    Connection.start_link(__MODULE__, config)
  end

  def flush(conn, options \\ []) do
    Connection.call(conn, {:flush, options})
  end

  def set(conn, item, options \\ []) when is_tuple(item) do
    Connection.call(conn, {:set, item, options})
  end

  @doc """
  Get a single value.

  ## Options
  * `verbose` (boolean, default false) Missing value will return `{:error, :not_found}`.
  * `cas` (boolean, default false) Return cas value along with key value.

  ## Examples

  ```
  {:ok, nil} = get(conn, "foo")

  {:error, :not_found} = get(conn, "foo", verbose: true)

  {:ok, "Callie"} = get(conn, "name")

  {:ok, {"Callie", 123}} = get(conn, "name", cas: true)
  ```
  """
  @spec get(t, binary, Keyword.t) :: get_result
  def get(conn, key, options \\ []) do
    Connection.call(conn, {:get, key, options})
  end

  def mset(conn, items, options \\ []) do
    Connection.call(conn, {:mset, items, options})
  end

  @doc """
  Get multiple values.

  ## Options
  * `verbose :: boolean \\\\ false` Missing value will return `{:error, :not_found}`.
  * `cas :: boolean \\\\ false` Return cas value along with key value.

  ## Examples
  ```
  {:ok, [{:ok, nil}, {:ok, "Callie"}]} = mget(conn, ["foo", "name"])

  {:ok, [{:error, :not_found}, {:ok, "Callie"}]} = mget(conn, ["foo", "name"], verbose: true)

  {:ok, [{:ok, nil}, {:ok, {"Callie", 123}]} = mget(conn, ["foo", "name"], cas: true)
  ```
  """
  @spec mget(t, [binary], Keyword.t) :: {:ok, [get_result]} | {:error, reason}
  def mget(conn, keys, options \\ []) do
    Connection.call(conn, {:mget, keys, options})
  end

  def noop(conn) do
    Connection.call(conn, :noop)
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

  def handle_call({:set, item, options}, _from, state) do
    %{socket: socket} = state

    item_opts = Keyword.take(options, [:expiry])

    with {:ok, item} <- normalize_item(item, item_opts, state),
      packet = Protocol.set(item),
      :ok <- :inet.setopts(socket, active: false),
      :ok <- :gen_tcp.send(socket, packet),
      {:ok, packet} <- Protocol.recv_packet(socket),
      :ok <- :inet.setopts(socket, active: true)
    do
      case packet.status do
        :ok -> if options[:cas] do
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

  def handle_call({:get, key, options}, _from, state) do
    %{socket: socket} = state

    packet = Protocol.get(key, options)

    with :ok <- :inet.setopts(socket, active: false),
      :ok <- :gen_tcp.send(socket, packet),
      {:ok, packet} <- Protocol.recv_packet(socket),
      :ok <- :inet.setopts(socket, active: true)
    do
      case packet.status do
        :ok ->
          with {:ok, value} <- decode(packet.value, packet.extras.flags, state) do
            if options[:cas] do
              {:reply, {:ok, {value, packet.cas}}, state}
            else
              {:reply, {:ok, value}, state}
            end
          else
            {:error, reason} -> {:reply, {:error, reason}, state}
          end

        :not_found -> if options[:verbose] do
          {:reply, {:error, :not_found}, state}
        else
          {:reply, {:ok, nil}, state}
        end

        reason -> {:reply, {:error, reason}, state}
      end
    else
      {:error, reason} -> {:disconnect, reason, state}
    end
  end

  def handle_call({:mset, items, options}, _from, state) do
    %{socket: socket} = state

    item_opts = Keyword.take(options, [:expiry])
    count = Enum.count(items)

    with {:ok, items} <- normalize_items(items, item_opts, state),
      packets = Enum.map(items, &Protocol.set/1),
      :ok <- :inet.setopts(socket, active: false),
      :ok <- :gen_tcp.send(socket, packets),
      {:ok, packets} <- Protocol.recv_packets(socket, count),
      :ok <- :inet.setopts(socket, active: true)
    do
      result = if options[:cas] do
        Enum.map(packets, fn
          %{status: :ok, cas: cas} -> {:ok, cas}
          %{status: reason} -> {:error, reason}
        end)
      else
        Enum.map(packets, fn
          %{status: :ok} -> :ok
          %{status: reason} -> {:error, reason}
        end)
      end

      if Enum.all?(result, & &1 == :ok) do
        {:reply, :ok, state}
      else
        {:reply, {:ok, result}, state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:mget, keys, options}, _from, state) do
    %{socket: socket} = state

    packets = Enum.map(keys, fn
      {key, _opts} -> Protocol.getkq(to_string(key))
      key -> Protocol.getkq(to_string(key))
    end)

    packets = [packets, Protocol.noop()]

    with :ok <- :inet.setopts(socket, active: false),
      :ok <- :gen_tcp.send(socket, packets),
      {:ok, packets} <- Protocol.recv_packets(socket, :noop),
      :ok <- :inet.setopts(socket, active: true)
    do
      values_by_key = Enum.reduce_while(packets, %{}, fn packet, acc ->
        case packet.opcode do
          :noop -> {:halt, acc}
          _ -> {:cont, Map.put(acc, packet.key, {packet.value, packet.cas})}
        end
      end)

      cas = Keyword.get(options, :cas, false)

      responses = Enum.map(keys, fn key ->
        {key, opts} = case key do
          {key, opts} -> {key, opts}
          key -> {key, []}
        end

        cas = opts[:cas] || cas

        case {values_by_key[key], cas} do
          {nil, _} -> {:error, :not_found}
          {{value, _cas}, false} -> {:ok, value}
          {value_cas, true} -> {:ok, value_cas}
        end
      end)

      {:reply, {:ok, responses}, state}
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

  defp normalize_items(items, opts, state) do
    Enum.reduce_while(items, [], fn item, acc ->
      with {:ok, item} <- normalize_item(item, opts, state) do
        {:cont, [item | acc]}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      items -> {:ok, Enum.reverse(items)}
    end
  end

  defp normalize_item(item, opts, state) do
    item = case item do
      {key, value} -> {:ok, key, value, opts}
      {key, value, item_opts} -> {:ok, key, value, Keyword.merge(opts, item_opts)}
      _ -> {:error, :invalid_item}
    end

    with {:ok, key, value, opts} <- item,
      {:ok, value, flags} <- encode(value, state)
    do
      {:ok, {key, value, flags, opts}}
    end
  end

  defp encode(value, %{coder: nil}), do: {:ok, value, 0}
  defp encode(value, %{coder: coder}) do
    coder.encode(value)
  end

  defp decode(value, _flags, %{coder: nil}), do: {:ok, value}
  defp decode(value, flags, %{coder: coder}) do
    coder.decode(value, flags)
  end

end
