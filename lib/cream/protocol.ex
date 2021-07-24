defmodule Cream.Protocol do
  @moduledoc false

  @request  0x80
  @response 0x81

  @get    0x00
  @set    0x01
  @delete 0x04
  @flush  0x08
  @getq   0x09
  @noop   0x0a
  @getk   0x0c
  @getkq  0x0d
  @setq   0x11

  [
    {0x0000, :ok},
    {0x0001, :not_found},
    {0x0002, :exists},
    {0x0003, :too_large},
    {0x0004, :invalid_args},
    {0x0005, :no_stored},
    {0x0006, :non_numeric},
    {0x0007, :vbucket_error},
    {0x0008, :auth_error},
    {0x0009, :auth_cont},
    {0x0081, :unknown_cmd},
    {0x0082, :oom},
    {0x0083, :not_supported},
    {0x0084, :internal_error},
    {0x0085, :busy},
    {0x0086, :temp_failure}
  ]
  |> Enum.each(fn {code, atom} ->
    def status_to_atom(unquote(code)), do: unquote(atom)
  end)

  defmacrop bytes(n) do
    bytes = n*8
    quote do: size(unquote(bytes))
  end

  def noop do
    [
      <<@request::bytes(1)>>,
      <<@noop::bytes(1)>>,
      <<0x00::bytes(2)>>,
      <<0x00::bytes(1)>>,
      <<0x00::bytes(1)>>,
      <<0x00::bytes(2)>>,
      <<0x00::bytes(4)>>,
      <<0x00::bytes(4)>>,
      <<0x00::bytes(8)>>,
    ]
  end

  def flush(options \\ []) do
    expiry = Keyword.get(options, :ttl, 0)

    [
      <<@request::bytes(1)>>,
      <<@flush::bytes(1)>>,
      <<0x00::bytes(2)>>,
      <<0x04::bytes(1)>>,
      <<0x00::bytes(1)>>,
      <<0x00::bytes(2)>>,
      <<0x04::bytes(4)>>,
      <<0x00::bytes(4)>>,
      <<0x00::bytes(8)>>,
      <<expiry::bytes(4)>>
    ]
  end

  def delete(key) do
    key_size = byte_size(key)

    [
      <<@request::bytes(1)>>,
      <<@delete::bytes(1)>>,
      <<key_size::bytes(2)>>,
      <<0x00::bytes(1)>>,
      <<0x00::bytes(1)>>,
      <<0x00::bytes(2)>>,
      <<key_size::bytes(4)>>,
      <<0x00::bytes(4)>>,
      <<0x00::bytes(8)>>,
      key
    ]
  end

  def set({key, value, ttl, cas, flags}) do
    key_size = byte_size(key)
    value_size = byte_size(value)
    body_size = key_size + value_size + 8

    [
      @request,
      @set,
      <<key_size::bytes(2)>>,
      0x08,
      0x00,
      <<0x00::bytes(2)>>,
      <<body_size::bytes(4)>>,
      <<0x00::bytes(4)>>,
      <<cas::bytes(8)>>,
      <<flags::bytes(4)>>,
      <<ttl::bytes(4)>>,
      key,
      value
    ]
  end

  def setq(key, value, flags, options \\ []) do
    expiry = Keyword.get(options, :expiry, 0)
    cas = Keyword.get(options, :cas, 0)

    key_size = byte_size(key)
    value_size = byte_size(value)
    body_size = key_size + value_size + 8

    [
      @request,
      @setq,
      <<key_size::bytes(2)>>,
      0x08,
      0x00,
      <<0x00::bytes(2)>>,
      <<body_size::bytes(4)>>,
      <<0x00::bytes(4)>>,
      <<cas::bytes(8)>>,
      <<flags::bytes(4)>>,
      <<expiry::bytes(4)>>,
      key,
      value
    ]
  end

  def get(key) do
    key_size = byte_size(key)

    [
      @request,
      @get,
      <<key_size::size(16)>>,
      0x00,
      0x00,
      <<0x00::size(16)>>,
      <<key_size::size(32)>>,
      <<0x00::size(32)>>,
      <<0x00::size(64)>>,
      key
    ]
  end

  def getkq(key, _options \\ []) do
    key_size = byte_size(key)

    [
      @request,
      @getkq,
      <<key_size::size(16)>>,
      0x00,
      0x00,
      <<0x00::size(16)>>,
      <<key_size::size(32)>>,
      <<0x00::size(32)>>,
      <<0x00::size(64)>>,
      key
    ]
  end

  def recv_packet(socket) do
    with {:ok, header, body} <- recv_packet_data(socket) do
      {:ok, parse_packet(header, body)}
    end
  end

  def recv_packets(socket, how, packets \\ [])

  def recv_packets(socket, :noop, packets) do
    with {:ok, packet} <- recv_packet(socket) do
      case packet do
        %{opcode: @noop} -> {:ok, Enum.reverse(packets)}
        packet -> recv_packets(socket, :noop, [packet | packets])
      end
    end
  end

  def recv_packets(_socket, 0, packets) do
    {:ok, Enum.reverse(packets)}
  end

  def recv_packets(socket, count, packets) when is_integer(count) do
    with {:ok, packet} <- recv_packet(socket) do
      recv_packets(socket, count-1, [packet | packets])
    end
  end

  defp recv_packet_data(socket) do
    with {:ok, header} <- :gen_tcp.recv(socket, 24) do
      <<_::bytes(8), body_length::bytes(4), _::binary>> = header
      if body_length == 0 do
        {:ok, header, ""}
      else
        with {:ok, body} <- :gen_tcp.recv(socket, body_length) do
          {:ok, header, body}
        end
      end
    end
  end

  defp parse_packet(header, body) do
    <<
      @response,
      opcode::bytes(1),
      key_length::bytes(2),
      extra_length::bytes(1),
      _data_type::bytes(1),
      status::bytes(2),
      body_length::bytes(4),
      _opaque::bytes(4),
      cas::bytes(8),
    >> = header

    value_length = body_length - extra_length - key_length

    <<
      extras::binary-size(extra_length),
      key::binary-size(key_length),
      value::binary-size(value_length)
    >> = body

    %{
      opcode: opcode,
      status: status_to_atom(status),
      cas: cas,
      key: key,
      value: value,
      extras: parse_extras(opcode, extras)
    }
  end

  defp parse_extras(_opcode, ""), do: %{}
  defp parse_extras(opcode, extras) when opcode in [@get, @getq, @getk, @getkq] do
    <<flags::bytes(4)>> = extras
    %{flags: flags}
  end
  defp parse_extras(_opcode, _extras), do: %{}

end
