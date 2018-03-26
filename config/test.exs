use Mix.Config

config :cream, Test.Cluster,
  servers: ["localhost:11201", "localhost:11202", "localhost:11203"],
  memcachex: [coder: Memcache.Coder.JSON]

config :logger,
  level: :info
