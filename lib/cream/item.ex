defmodule Cream.Item do
  defstruct [:key, :value, :raw_value, ttl: 0, cas: 0, flags: 0, coder: nil]

  def from_args({key, value}) do
    {:ok, %__MODULE__{key: key, value: value, raw_value: value}}
  end

  def from_args({key, value, opts}) do
    with {:ok, item} <- from_args({key, value}) do
      {:ok, struct!(item, opts)}
    end
  end

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
