defmodule Cream.Error do
  @moduledoc """
  Semantic errors returned by memcached server.

  The `:reason` field corresponds to a packet's status as described by
  the memcached binary protocol.

  Notable reasons are...

  * `:not_found` - Key does not exist.
  * `:exists` - Usually a cas error.

  """

  defexception [:reason]

  @type t :: %__MODULE__{reason: atom}

  @impl Exception

  def exception(reason) when is_atom(reason) do
    %__MODULE__{reason: reason}
  end

  @impl Exception

  def message(e) do
    to_string(e.reason)
  end

end
