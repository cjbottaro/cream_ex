defmodule Cream.Coder.Gzip do
  use Bitwise

  @behaviour Cream.Coder

  def encode(value, flags) when is_binary(value) do
    {:ok, :zlib.gzip(value), flags ||| 0b10}
  end

  def encode(_value, _flags) do
    {:error, "cannot gzip non-binary values"}
  end

  def decode(value, flags) when (flags &&& 0b10) == 0b10 do
    if is_binary(value) do
      {:ok, :zlib.gunzip(value)}
    else
      {:error, "cannot gunzip non-binary values"}
    end
  end

  def decode(value, _flags) do
    {:ok, value}
  end

end
