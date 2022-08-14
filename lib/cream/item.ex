defmodule Cream.Item do
  @moduledoc """
  Represents a conceptual cache item.

  This is returned by read and write type operations when the `verbose: true`
  option is used.

  The memcached protocol doesn't give a way get the ttl of a key, so on reads
  the `:ttl` field will be `:unknown`.

  `:raw_value` is the binary that is actually stored in memcached.

  `:value` is before (write) or after (read) `:coder` serialization has
  been applied. It can be any kind of term.

  """
  defstruct [:key, :value, :raw_value, ttl: 0, cas: 0, flags: 0, coder: nil]

  @type t :: %__MODULE__{
    key: binary,
    value: term,
    raw_value: binary,
    ttl: non_neg_integer,
    cas: non_neg_integer,
    flags: non_neg_integer,
    coder: nil | Cream.Coder.t | [Cream.Coder.t]
  }

  @doc false
  @spec from_args({binary, term}) :: {:ok, t}
  def from_args({key, value}) do
    {:ok, %__MODULE__{key: key, value: value, raw_value: value}}
  end

  @doc false
  @spec from_args({binary, term, Keyword.t}) :: {:ok, t}
  def from_args({key, value, opts}) do
    with {:ok, item} <- from_args({key, value}) do
      {:ok, struct!(item, opts)}
    end
  end

  @doc false
  @spec from_packet(map, Keyword.t) :: {:ok, t}
  def from_packet(packet, fields \\ []) do
    item = struct(__MODULE__, [
      key: packet.key || fields[:key],
      value: packet.value,
      raw_value: packet.value,
      ttl: :unknown,
      cas: packet.cas,
      flags: packet.extras.flags
    ])

    {:ok, item}
  end
end
