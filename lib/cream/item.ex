defmodule Cream.Item do
  defstruct [:key, :value, ttl: 0, cas: 0, flags: 0]

  def from_args({key, value}) do
    {:ok, %__MODULE__{key: key, value: value}}
  end

  def from_args({key, value, opts}) do
    {:ok, struct!(__MODULE__, Keyword.merge(opts, [key: key, value: value]))}
  end
end
