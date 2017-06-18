# Cream

A memcached client that connects to "clusters" of memcached servers and uses
consistent hashing for key routing.

Features
 * connect to a "cluster" of memcached servers
 * same consistent hashing algorithm as Ruby's Dalli gem
 * fetch with anonymous function
 * multi set
 * multi get
 * multi fetch
 * built in pooling via [poolboy](https://github.com/devinus/poolboy)
 * dynamically namespaced keys
 * complete supervision trees

## Installation

This hasn't been published to [hex.pm](https://hex.pm) yet so you have install via Github.

```elixir
def deps do
  [
    {:cream, git: "https://github.com/cjbottaro/cream.git"}
  ]
end
```

## Quickstart

```elixir
# Connects to localhost:11211 with worker pool of size 10
{:ok, cluster} = Cream.Cluster.start_link

# Single set and get
Cream.Cluster.set(cluster, {"name", "Callie"})
Cream.Cluster.get(cluster, "name")
# => "Callie"

# Single fetch
Cream.Cluster.fetch cluster, "some", fn ->
  "thing"
end
# => "thing"

# Multi set / multi get with list
Cream.Cluster.set(cluster, [{"name", "Callie"}, {"buddy", "Chris"}])
Cream.Cluster.get(cluster, ["name", "buddy"])
# => %{"name" => "Callie", "buddy" => "Chris"}

# Multi set / multi get with map
Cream.Cluster.set(cluster, %{"species" => "canine", "gender" => "female"})
Cream.Cluster.get(cluster, ["species", "gender"])
# => %{"species" => "canine", "gender" => "female"}

# Multi fetch
Cream.Cluster.fetch cluster, ["foo", "bar", "baz"], fn missing_keys ->
  Enum.map(missing_keys, &String.reverse/1)
end
# => %{"foo" => "oof", "bar" => "rab", "baz" => "zab"}
```

## Connecting to a cluster

```elixir
{:ok, cluster} = Cream.Cluster.start_link servers: ["cache01:11211", "cache02:11211"]
```

## Using modules

You can simplify access to your memcached cluster with modules.

```elixir
# In config/*.exs

config :cream, servers: ["cache01:11211", "cache02:11211"]
config :cream, pool: 5

# Elsewhere

defmodule MyCluster do
  use Cream.Cluster
end

MyCluster.start_link
MyCluster.get("foo")
```

## Using modules with more than one cluster

Yeah, this works too.

```elixir
# In config/*.exs

config :cream, clusters: [
  main: [
    servers: ["cache01:11211", "cache02:11211"],
    pool: 10
  ]
  other: [
    servers: ["cache03:11211"],
    pool: 5
  ]
]

# Elsewhere

defmodule MyMainCluster do
  use Cream.Cluster, :main
end

defmodule MyOtherCluster do
  use Cream.Cluster, :other
end

MyMainCluster.start_link
MyOtherCluster.start_link

MyMainCluster.set("foo", "bar")
MyOtherCluster.set("foo", "not bar")

"bar" = MyMainCluster.get("foo")
"not bar" = MyOtherCluster.get("foo")
```
## Supervision

Everything is supervised, even the supervisors, so it really does make a
supervision tree.

A "cluster" is really a poolboy pool of cluster supervisors. A cluster
supervisor supervises each `Memcache.Connection` process and one
`Cream.Cluster.Worker` process.

No pids are stored anywhere, but instead processes are tracked via Elixir's
`Registry` module.

The results of `Cream.Cluster.start_link` and `MyClusterModule.start_link` can
be inserted into your application's supervision tree.

## Running the tests

You have to have Docker and Docker Compose installed...
```
docker-compose up -d
mix test

# Stop and clean up containers
docker-compose stop
docker-compose rm
```

## TODO

* Module documentation at [https://hexdocs.pm/cream](https://hexdocs.pm/cream)
* Server weights
* Parallel memcached requests
