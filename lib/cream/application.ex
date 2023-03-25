defmodule Cream.Application do
  @moduledoc false

  use Application

  def start(_, _) do
    :ok = Cream.Logger.init()

    children = [
      # {Cream.Client, [name: Cream]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

end
