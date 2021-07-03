defmodule Cream.Coder.Jason do
  use Bitwise

  @behaviour Cream.Coder

  def encode(value, flags) do
    with {:ok, json} <- Jason.encode(value) do
      {:ok, json, flags ||| 0b01}
    end
  end

  def decode(value, flags) when (flags &&& 0b01) == 0b01 do
    with {:ok, json} <- Jason.decode(value) do
      {:ok, json}
    end
  end

  def decode(value, _flags) do
    {:ok, value}
  end

end
