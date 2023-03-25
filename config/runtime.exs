import Config

{json, 0} = System.cmd("docker", ~w(compose ps --format json))

containers = Jason.decode!(json)

servers =[
  "cream_ex-memcached-1",
  "cream_ex-memcached-2",
  "cream_ex-memcached-3"
]
|> Enum.map(fn name ->
  container = Enum.find(containers, & &1["Name"] == name)

  port = container["Publishers"]
  |> List.first()
  |> Map.get("PublishedPort")

  "localhost:#{port}"
end)

config :cream, Cream.Connection, server: List.first(servers)
config :cream, Cream.Client, servers: servers
