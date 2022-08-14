defmodule Cream.Coder do
  @moduledoc """
  Value serialization.

  Coders serialize and deserialize values when writing and reading to memcached.

  ## JSON example

  Let's make a simple JSON coder...

  ```
  defmodule JsonCoder do
    use Bitwise

    @behaviour Cream.Coder

    # Do not encode binary values.
    def encode(value, flags) when is_binary(value) do
      {:ok, value, flags &&& 0b0}
    end

    # Do encode everything else.
    def encode(value, flags) do
      with {:ok, json} <- Jason.encode(value) do
        {:ok, json, flags ||| 0b1}
      end
    end

    # Flags indicates the value isn't encoded.
    def decode(value, flags) when (flags ||| 0b1) == 0 do
      {:ok, value}
    end

    # Flags indicate we have an encoded value.
    def decode(json, flags) when (flags ||| 0b1) == 0b1 do
      with {:ok, value} <- Jason.decode(json) do
        {:ok, value}
      end
    end

  end
  ```

  Notice we set a the bit `0b1` on flags to indicate the value is serialized.
  When the value is not serialized, we unset the bit.

  Now let's see the coder in action. We use two connections, one that uses the
  coder and one that doesn't.
  ```
  {:ok, json_conn} = Cream.Connection.start_link(coder: JsonCoder)
  {:ok, raw_conn} = Cream.Connection.start_link()

  # JsonCoder serializes maps, but leaves strings alone.

  iex(1)> Cream.Connection.set(json_conn, "foo", %{"hello" => "world"})
  :ok

  iex(1)> Cream.Connection.get(json_conn, "foo")
  {:ok, %{"hello" => "world"}}

  iex(1)> Cream.Connection.set(json_conn, "bar", "hello world")
  :ok

  iex(1)> Cream.Connection.get(json_conn, "bar")
  {:ok, "hello world"}

  # We can verify this by using the connection that doesn't use the coder.

  iex(1)> Cream.Connection.get(raw_conn, "foo")
  {:ok, "{\\"hello\\":\\"world\\"}"}

  iex(1)> Cream.Connection.get(raw_conn, "bar")
  {:ok, "hello world"}
  ```

  ## Multiple coders

  You can specify a chain of coders.

  ```
  {:ok, :conn} = Cream.Connection.start_link(coder: [JsonCoder, GzipCoder])
  ```

  Encoding is done in the order specified and decoding is done in the reverse
  order.
  """

  @type value :: term
  @type flags :: integer()
  @type reason :: term

  @doc """
  Encode a value and set flags.
  """
  @callback encode(value, flags) :: {:ok, value, flags} | {:error, reason}

  @doc """
  Decode a value based on flags.
  """
  @callback decode(value, flags) :: {:ok, value} | {:error, reason}

  def encode_item(%Cream.Item{} = item, conn, coder) do
    with {:ok, coder} <- fetch_coder(conn, coder),
      {:ok, value, flags} <- encode_value(coder, item.value, item.flags)
    do
      {:ok, %{item | raw_value: value, flags: flags, coder: coder}}
    else
      :not_found -> {:ok, item}
      error -> error
    end
  end

  @doc false
  def encode_value(coder, value, flags) when is_atom(coder) do
    coder.encode(value, flags)
  end

  @doc false
  def encode_value(coders, value, flags) when is_list(coders) do
    Enum.reduce_while(coders, {:ok, value, flags}, fn coder, {:ok, value, flags} ->
      case encode_value(coder, value, flags) do
        {:ok, value, flags} -> {:cont, {:ok, value, flags}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc false
  def decode_item(%Cream.Item{} = item, conn, coder) do
    with {:ok, coder} <- fetch_coder(conn, coder),
      {:ok, value} <- decode_value(coder, item.raw_value, item.flags)
    do
      {:ok, %{item | value: value, coder: coder}}
    else
      :not_found -> {:ok, item}
      error -> error
    end
  end

  @doc false
  def decode_value(coder, value, flags) when is_atom(coder) do
    coder.decode(value, flags)
  end

  @doc false
  def decode_value(coders, value, flags) when is_list(coders) do
    Enum.reverse(coders)
    |> Enum.reduce_while({:ok, value}, fn coder, {:ok, value} ->
      case decode_value(coder, value, flags) do
        {:ok, value} -> {:cont, {:ok, value}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp fetch_coder(_conn, false), do: :not_found
  defp fetch_coder(_conn, coder) when coder != nil, do: {:ok, coder}
  defp fetch_coder(conn, _coder) do
    case Connection.call(conn, :fetch_coder) do
      {:ok, nil} -> :not_found
      result -> result
    end
  end

end
