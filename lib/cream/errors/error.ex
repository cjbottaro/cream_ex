defmodule Cream.Error do
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
