defmodule Cream.ConnectionError do
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
