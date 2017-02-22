use Mix.Config

config :cream, Repo,
  adapter: Ecto.Adapters.Postgres,
  pool: Ecto.Adapters.SQL.Sandbox,
  database: "cream_test"

config :cream,
  ecto_repos: [Repo],
  hosts: ["localhost:11211"]

config :logger,
  level: :info
