defmodule Cream.ConnectionError do
  @moduledoc """
  Server connection errors.

  `:reason` will be things like `:nxdomain` and `:econnrefused` as returned by
  Erlang's `:gen_tcp` module.

  `:server` will be a binary like `"localhost:11211"`.
  """
  defexception [:reason, :server]

  @type t :: %__MODULE__{reason: atom, server: binary}

  @impl Exception

  def exception(fields) when is_list(fields) do
    struct!(__MODULE__, fields)
  end

  def exception(reason, server) do
    %__MODULE__{reason: reason, server: server}
  end

  @impl Exception

  def message(e) do
    case e do
      %{reason: reason, server: nil} -> to_string(reason)
      %{reason: reason, server: server} -> "#{reason} - #{server}"
    end
  end

end
