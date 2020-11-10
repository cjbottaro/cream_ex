defmodule Cream.Packet do

  @request_magic  0x80
  @response_magic 0x81

  defstruct [
    magic:              @request_magic,
    opcode:             nil,
    key_length:         0x0000,
    extra_length:      0x00,
    data_type:          0x00,
    vbucket_id:         0x0000,
    status:             0x0000,
    total_body_length:  0x00000000,
    opaque:             0x00000000,
    cas:                0x0000000000000000,
    extra:             "",
    key:                "",
    value:              ""
  ]

  @atom_to_opcode %{
    get: 0x00,
    set: 0x01,
    flush: 0x08,
    getq: 0x09,
    noop: 0x0a,
    getk: 0x0c,
    getkq: 0x0d,
    setq: 0x11,
  }

  @atom_to_status %{
    ok:             0x0000,
    not_found:      0x0001,
    exists:         0x0002,
    too_large:      0x0003,
    invalid_args:   0x0004,
    not_stored:     0x0005,
    non_numeric:    0x0006,
    vbucket_error:  0x0007,
    auth_error:     0x0008,
    auth_cont:      0x0009,
    unknown_cmd:    0x0081,
    oom:            0x0082,
    not_supported:  0x0083,
    internal_error: 0x0084,
    busy:           0x0085,
    temp_failure:   0x0086
  }

  @opcode_to_atom Enum.map(@atom_to_opcode, fn {k, v} -> {v, k} end) |> Map.new()
  @status_to_atom Enum.map(@atom_to_status, fn {k, v} -> {v, k} end) |> Map.new()

  defmacrop bytes(n) do
    bytes = n*8
    quote do: size(unquote(bytes))
  end

  def new(opcode, options \\ []) do
    if not Map.has_key?(@atom_to_opcode, opcode) do
      raise "unknown opcode #{opcode}"
    end

    packet = %__MODULE__{
      magic: @request_magic,
      opcode: opcode,
    }

    packet = %{packet |
      extra: serialize_extra(opcode, options),
      key: options[:key] || "",
      value: options[:value] || ""
    }

    extra_length  = IO.iodata_length(packet.extra)
    key_length    = byte_size(packet.key)
    value_length  = byte_size(packet.value)

    %{packet |
      extra_length: extra_length,
      key_length: key_length,
      total_body_length: extra_length + key_length + value_length
    }
  end

  def serialize_extra(opcode, options) when opcode in [:set, :setq] do
    flags      = options[:flags] || 0
    expiration = options[:expiration] || 0

    [
      <<flags      :: bytes(4)>>,
      <<expiration :: bytes(4)>>,
    ]
  end

  def serialize_extra(_opcode, _options), do: []

  def deserialize_extra(_opcode, ""), do: %{}

  def deserialize_extra(opcode, data) when opcode in [:get, :getq, :getk, :getkq] do
    <<flags :: bytes(4)>> = data
    %{flags: flags}
  end

  def deserialize_extra(_opcode, _data), do: %{}

  def serialize(packet) when packet.magic == @request_magic do
    opcode = @atom_to_opcode[packet.opcode]

    [
      <<packet.magic             :: bytes(1) >>,
      <<opcode                   :: bytes(1) >>,
      <<packet.key_length        :: bytes(2) >>,
      <<packet.extra_length     :: bytes(1) >>,
      <<packet.data_type         :: bytes(1) >>,
      <<packet.vbucket_id        :: bytes(2) >>,
      <<packet.total_body_length :: bytes(4) >>,
      <<packet.opaque            :: bytes(4) >>,
      <<packet.cas               :: bytes(8) >>,
      packet.extra,
      packet.key,
      packet.value
    ]
  end

  def deserialize_header(data) do
    <<
      @response_magic   :: bytes(1),
      opcode            :: bytes(1),
      key_length        :: bytes(2),
      extra_length     :: bytes(1),
      data_type         :: bytes(1),
      status            :: bytes(2),
      total_body_length :: bytes(4),
      opaque            :: bytes(4),
      cas               :: bytes(8)
    >> = data

    %__MODULE__{
      magic:              @response_magic,
      opcode:             @opcode_to_atom[opcode],
      key_length:         key_length,
      extra_length:      extra_length,
      data_type:          data_type,
      status:             @status_to_atom[status],
      total_body_length:  total_body_length,
      opaque:             opaque,
      cas:                cas
    }
  end

  def deserialize_body(packet, data) do
    extra_length = packet.extra_length
    key_length = packet.key_length

    <<
      extra :: binary-size(extra_length),
      key :: binary-size(key_length),
      value :: binary
    >> = data

    extra = deserialize_extra(packet.opcode, extra)

    %{packet | extra: extra, key: key, value: value}
  end

end
