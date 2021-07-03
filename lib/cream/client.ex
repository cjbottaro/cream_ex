defmodule Cream.Client do
  @behaviour NimblePool

  @defaults [
    pool_size: 5,
    lazy: true,
    servers: ["localhost:11211"]
  ]
  def defaults, do: @defaults

  def config do
    Keyword.merge(
      @defaults,
      Application.get_application(__MODULE__)
      |> Application.get_env(__MODULE__, [])
    )
  end

  @impl NimblePool
  def init_pool(config) do
    config = Map.new(config)
    |> Map.merge(%{
      continuum: Cream.Continuum.new(config[:servers])
    })

    {:ok, config}
  end

  @impl NimblePool
  def init_worker(config) do
    worker = Map.new(config[:servers], fn server ->
      {:ok, conn} = Cream.Connection.start_link(server: server)
      {server, conn}
    end)

    {:ok, worker, config}
  end

  @impl NimblePool
  def handle_checkout(:checkout, _from, worker, config) do
    client = Map.put(config, :connections, worker)
    {:ok, client, worker, config}
  end

  def child_spec(config \\ []) do
    config = Keyword.merge(config(), config)

    Keyword.take(config, [:pool_size, :lazy])
    |> Keyword.put(:worker, {__MODULE__, config})
    |> NimblePool.child_spec()
  end

  def start_link(config \\ []) do
    %{start: {m, f, a}} = child_spec(config)
    apply(m, f, a)
  end

  def checkout(pool, f) do
    NimblePool.checkout!(pool, :checkout, fn _, client ->
      {f.(client), client}
    end)
  end

end
