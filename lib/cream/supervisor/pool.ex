defmodule Cream.Supervisor.Pool do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(nil) do
    children = [
      worker(Cream.ConnectionPool, [], restart: :transient)
    ]
    supervise(children, strategy: :simple_one_for_one)
  end

  def start_child(options \\ [], gen_options \\ [], func) do
    Supervisor.start_child(__MODULE__, [options, gen_options, func])
  end

end
