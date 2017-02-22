defmodule Cream do

  require Logger
  alias Cream.{Command}

  def new(options \\ []), do: Cream.Cluster.new(options)

  defdelegate flush(pool_or_cluster \\ :__default__, options \\ []), to: Command.Flush
  defdelegate fetch(pool_or_cluster \\ :__default__, keys, func), to: Command.Fetch
  defdelegate set(pool_or_cluster \\ :__default__, keys_and_values), to: Command.Set
  defdelegate get(pool_or_cluster \\ :__default__, keys), to: Command.Get

end
