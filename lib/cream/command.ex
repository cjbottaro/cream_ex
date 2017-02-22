defmodule Cream.Command do

  defmacro __using__(_) do
    quote do
      alias Cream.{Cluster, ConnectionPool}
      require Logger
    end
  end

end
