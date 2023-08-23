defmodule Cream.Coder.ErlangTerm do
  @moduledoc """
  A coder using :`erlang.term_to_binary/1`.

  Uses the first bit on flags.
  """
  import Bitwise

  @behaviour Cream.Coder

  def encode(value, flags) do
    {:ok, :erlang.term_to_binary(value), flags ||| 0b01}
  end

  def decode(value, flags) when (flags &&& 0b01) == 0b01 do
    {:ok, :erlang.binary_to_term(value)}
  end

  def decode(value, _flags) do
    {:ok, value}
  end

end
