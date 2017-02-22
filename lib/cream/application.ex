defmodule Cream.Application do
  use Application

  def start(_, _) do
    return = Cream.Supervisor.start_link

    if hosts = Application.get_env(:cream, :hosts) do
      pool_size = Application.get_env(:cream, :pool, 10)
      {:ok, _} = Cream.Supervisor.Pool.start_child [size: pool_size], [name: :__default__], fn ->
        Cream.Cluster.new(hosts: hosts)
      end
    end

    return
  end
end
