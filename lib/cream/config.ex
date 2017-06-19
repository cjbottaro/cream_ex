defmodule Cream.Config do

  defmodule Error, do: defexception message: "configuration error"

  @default_servers ["localhost:11211"]
  @default_pool 10

  def default_servers, do: @default_servers
  def default_pool, do: @default_pool

  def get(name \\ nil) do
    [
      servers: servers(name),
      pool: pool(name),
      memcachex: memcachex(name),
    ] |> Keyword.delete(:memcachex, nil)
  end

  def servers(name \\ nil)

  def servers(nil) do
    Application.get_env(:cream, :servers, @default_servers)
  end

  def servers(name) do
    config_for(name) |> Keyword.get(:servers, @default_servers)
  end

  def pool(name \\ nil)

  def pool(nil) do
    Application.get_env(:cream, :pool, @default_pool)
  end

  def pool(name) do
    config_for(name) |> Keyword.get(:pool, @default_pool)
  end

  def memcachex(nil) do
    Application.get_env(:cream, :memcachex)
  end

  def memcachex(name) do
    config_for(name) |> Keyword.get(:memcachex)
  end

  defp config_for(name) do
    Application.get_env(:cream, :clusters)
      |> Keyword.get(name)
      || raise Error, message: "cluster #{inspect name} is not configured"
  end

end
