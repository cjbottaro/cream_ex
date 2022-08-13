import Config

{:ok, _apps} = Application.ensure_all_started(:finch)
{:ok, _pid} = Finch.start_link(name: Finch)

{:ok, resp} = Finch.build(:get, "http://localhost/containers/json", [], nil, unix_socket: "/var/run/docker.sock")
|> Finch.request(Finch)

servers = Jason.decode!(resp.body)
|> Enum.reduce([], fn container, acc ->
  name = Enum.find_value(container["Names"], fn name ->
    if String.starts_with?(name, "/cream-ex-memcached-") do
      name
    else
      false
    end
  end)

  if name do
    [%{"PublicPort" => port}] = container["Ports"]
    [{name, port} | acc]
  else
    acc
  end
end)
|> Enum.sort()
|> Enum.map(fn {_name, port} -> "localhost:#{port}" end)

config :cream, Cream.Connection, server: Enum.at(servers, 0)
config :cream, Cream.Client, servers: servers

:ok = NimblePool.stop(Finch)
