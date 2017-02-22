defmodule Cream.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil)
  end

  def init(nil) do
    children = [
      worker(Registry, [:unique, Cream.Registry]),
      worker(Cream.Supervisor.Pool, []),
      worker(Cream.Supervisor.Connection, [])
    ]
    supervise(children, strategy: :one_for_one)
  end

end
