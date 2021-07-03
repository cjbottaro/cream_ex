defmodule Cream.Coder do

  @type value :: term
  @type flags :: integer()
  @type reason :: term

  @callback encode(value, flags) :: {:ok, value, flags} | {:error, reason}
  @callback decode(value, flags) :: {:ok, value} | {:error, reason}

  @doc false
  def apply_encode(coder, value, flags) when is_atom(coder) do
    coder.encode(value, flags)
  end

  @doc false
  def apply_encode(coders, value, flags) when is_list(coders) do
    Enum.reduce_while(coders, {:ok, value, flags}, fn coder, {:ok, value, flags} ->
      case apply_encode(coder, value, flags) do
        {:ok, value, flags} -> {:cont, {:ok, value, flags}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc false
  def apply_decode(coder, value, flags) when is_atom(coder) do
    coder.decode(value, flags)
  end

  @doc false
  def apply_decode(coders, value, flags) when is_list(coders) do
    Enum.reduce_while(coders, {:ok, value}, fn coder, {:ok, value} ->
      case apply_decode(coder, value, flags) do
        {:ok, value} -> {:cont, {:ok, value}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

end
