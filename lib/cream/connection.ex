defmodule Cream.Connection do
  use Connection
  require Logger
  alias Cream.Packet

  @defaults [
    server: "localhost:11211"
  ]

  def start_link(options \\ []) do
    options = Keyword.merge(@defaults, options)
    Connection.start_link(__MODULE__, options)
  end

  def send_packets(conn, packets) do
    Connection.call(conn, {:send_packets, packets})
  end

  def recv_packets(conn, count) do
    Connection.call(conn, {:recv_packets, count})
  end

  def flush(conn, options \\ []) do
    with :ok <- send_packets(conn, [Packet.new(:flush, options)]),
      {:ok, [packet]} <- recv_packets(conn, 1)
    do
      packet.status
    end
  end

  def get(conn, key, options \\ []) do
    args = Keyword.put(options, :key, key)
    Connection.call(conn, {:get, args})
  end

  def set(conn, item, options \\ []) do
    Connection.call(conn, {:set, item, options})
  end

  def mget(conn, keys, options \\ []) do
    Connection.call(conn, {:mget, keys, options})
  end

  def init(options) do
    state = %{
      options: options,
      socket: nil,
    }

    {:connect, :init, state}
  end

  def connect(_context, state) do
    server = state.options[:server]
    url = "tcp://#{server}"

    case Socket.connect(url) do
      {:ok, socket} -> {:ok, %{state | socket: socket}}
      {:error, reason} ->
        Logger.warn("#{server} #{reason}")
        {:backoff, 1000, state}
    end
  end

  def handle_call({:send_packets, packets}, _from, state) do
    {:reply, do_send_packets(state.socket, packets), state}
  end

  def handle_call({:recv_packets, count}, _from, state) do
    {:reply, do_recv_packets(state.socket, count), state}
  end

  def handle_call({:get, args}, _from, state) do
    retval = with :ok <- do_send_packets(state.socket, [Packet.new(:get, args)]),
      {:ok, [packet]} <- do_recv_packets(state.socket, 1)
    do
      cond do
        packet.status == :not_found -> nil
        args[:cas] -> {:ok, {packet.value, packet.cas}}
        true -> {:ok, packet.value}
      end
    end

    {:reply, retval, state}
  end

  def handle_call({:set, item, args}, _from, state) do
    {key, value, cas} = case item do
      {key, value} -> {key, value, 0}
      {key, value, cas} -> {key, value, cas}
    end

    args = Keyword.merge(args, [key: key, value: value, cas: cas])

    retval = with :ok <- do_send_packets(state.socket, [Packet.new(:set, args)]),
      {:ok, [packet]} <- do_recv_packets(state.socket, 1)
    do
      packet.status
    end

    {:reply, retval, state}
  end

  def handle_call({:mget, keys, options}, _from, state) do
    packets = Enum.map(keys, fn key ->
      Packet.new(:getkq, Keyword.put(options, :key, key))
    end)

    # Eww, no good way to append to list.
    packets = packets ++ [Packet.new(:noop)]

    retval = with :ok <- do_send_packets(state.socket, packets),
      {:ok, packets} <- do_recv_packets(state.socket, :noop)
    do
      Enum.reduce(packets, %{}, fn
        packet, results when packet.opcode == :noop -> results
        packet, results -> Map.put(results, packet.key, packet.value)
      end)
    end

    {:reply, retval, state}
  end

  defp do_send_packets(socket, packets) do
    Enum.reduce_while(packets, :ok, fn packet, _result ->
      case Socket.Stream.send(socket, Packet.serialize(packet)) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp do_recv_packets(socket, :noop) do
    Stream.repeatedly(fn -> do_recv_packet(socket) end)
    |> Enum.reduce_while([], fn
      {:ok, packet}, packets -> if packet.opcode == :noop do
        {:halt, [packet | packets]}
      else
        {:cont, [packet | packets]}
      end
      error, _packets -> {:halt, error}
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      packets -> {:ok, Enum.reverse(packets)}
    end
  end

  defp do_recv_packets(socket, count) do
    Enum.reduce_while(1..count, [], fn _i, packets ->
      case do_recv_packet(socket) do
        {:ok, packet} -> {:cont, [packet | packets]}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      packets -> {:ok, Enum.reverse(packets)}
    end
  end

  defp do_recv_packet(socket) do
    with {:ok, data} <- do_recv_header(socket),
      packet = Packet.deserialize_header(data),
      {:ok, data} <- do_recv_body(socket, packet)
    do
      {:ok, Packet.deserialize_body(packet, data)}
    else
      error -> error
    end
  end

  defp do_recv_header(socket) do
    Socket.Stream.recv(socket, 24)
  end

  defp do_recv_body(_socket, packet) when packet.total_body_length == 0 do
    {:ok, ""}
  end

  defp do_recv_body(socket, packet) when packet.total_body_length > 0 do
    Socket.Stream.recv(socket, packet.total_body_length)
  end

end
