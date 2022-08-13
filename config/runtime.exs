import Config

{json, 0} = System.cmd("docker", ~w(compose ps --format json))

servers = Jason.decode!(json)
|> Enum.sort_by(& &1["Name"])
|> Enum.map(fn container ->
  port = container["Publishers"]
  |> List.first()
  |> Map.get("PublishedPort")

  "localhost:#{port}"
end)

config :cream, Cream.Connection, server: List.first(servers)
config :cream, Cream.Client, servers: servers
