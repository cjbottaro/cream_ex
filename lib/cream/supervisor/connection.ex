defmodule Cream.Supervisor.Connection do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(nil) do
    children = [
      worker(Memcache.Connection, [], restart: :transient)
    ]
    supervise(children, strategy: :simple_one_for_one)
  end

  def start_child(connection_options \\ [], options \\ []) do
    Supervisor.start_child(__MODULE__, [connection_options, options])
  end

end
