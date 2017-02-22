defmodule Cream.Command.Flush do
  use Cream.Command

  def flush(pool, options) when is_atom(pool) or is_pid(pool) do
    ConnectionPool.with pool, fn cluster -> flush(cluster, options) end
  end

  def flush(c = %Cluster{}, options) do
    ttl = Keyword.get(options, :ttl, 0)

    servers = c.continuum
      |> Tuple.to_list
      |> Enum.map(fn {server, _value} -> server end)
      |> Enum.uniq

    Enum.map servers, fn server ->
      Memcache.Connection.execute(server, :FLUSH, [ttl]) |> elem(0)
    end
  end

end
