defmodule Cream.Application do
  use Application

  def start(_, _) do
    import Supervisor.Spec, warn: false

    children = [
      worker(Registry, [:unique, Cream.Registry]),
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

end
