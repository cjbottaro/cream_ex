# Cache. Rules. Everything. Around. Me.

A Dalli compatible memcached client.

It uses the same consistent hashing algorithm to connect to a cluster of memcached servers.

## Table of contents

1. [Features](#features)
1. [Installation](#installation)
1. [Quickstart](#quickstart)
1. [Connecting to a cluster](#connecting-to-a-cluster)
1. [Using modules](#using-modules)
1. [Memcachex options](#memcachex-options)
1. [Memcachex API](#memcachex-api)
1. [Ruby compatibility](#ruby-compatibility)
1. [Supervision](#supervision)
1. [Instrumentation](#instrumentation)
1. [Documentation](https://hexdocs.pm/cream/Cream.Cluster.html)
1. [Running the tests](#running-the-tests)
1. [TODO](#todo)

## Features

 * connect to a "cluster" of memcached servers
 * compatible with Ruby's Dallie gem (same consistent hashing algorithm)
 * fetch with anonymous function
 * multi set
 * multi get
 * multi fetch
 * built in pooling via [poolboy](https://github.com/devinus/poolboy)
 * complete supervision trees
 * [fully documented](https://hexdocs.pm/cream/Cream.Cluster.html)
 * instrumentation with the [Instrumentation](https://hexdocs.pm/instrumentation) package.


## Installation

In your `mix.exs` file...

```elixir
def deps do
  [
    {:cream, ">= 0.1.0"}
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

You can use modules to configure clusters, exactly like how Ecto repos work.

```elixir
# In config/*.exs

config :my_app, MyCluster,
  servers: ["cache01:11211", "cache02:11211"],
  pool: 5

# Elsewhere

defmodule MyCluster do
  use Cream.Cluster, otp_app: :my_app

  # Optional callback to do runtime configuration.
  def init(config) do
    # config = Keyword.put(config, :pool, System.get_env("POOL_SIZE"))
    {:ok, config}
  end
end

MyCluster.start_link
MyCluster.get("foo")
```

## Memcachex options

Cream uses Memcachex for individual connections to the cluster. You can pass
options to Memcachex via `Cream.Cluster.start_link/1`:

```elixir
Cream.Cluster.start_link(
  servers: ["localhost:11211"],
  memcachex: [ttl: 3600, namespace: "foo"]
)
```

Or if using modules:

```elixir
use Mix.Config

config :my_app, MyCluster,
  servers: ["localhost:11211"],
  memcachex: [ttl: 3600, namespace: "foo"]

MyCluster.start_link
```

Any option you can pass to
[`Memcache.start_link`](https://hexdocs.pm/memcachex/Memcache.html#start_link/2),
you can pass via the `:memcachex` option for `Cream.Cluster.start_link`.

## Memcachex API

`Cream.Cluster`'s API is very small: `get`, `set`, `fetch`, `flush`. It may
expand in the future, but for now, you can access Memcachex's API directly
if you need.

Cream will still provide worker pooling and key routing, even when using
Memcachex's API directly.

If you are using a single key, things are pretty straight forward...

```elixir
results = Cream.Cluster.with_conn cluster, key, fn conn ->
  Memcache.get(conn, key)
end
```

It gets a bit more complex with a list of keys...

```elixir
results = Cream.Cluster.with_conn cluster, keys, fn conn, keys ->
  Memcache.multi_get(conn, keys)
end
# results will be a list of whatever was returned by the invocations of the given function.
```

Basically, Cream will group keys by memcached server and then call the provided
function for each group and return a list of the results of each call.

## Ruby compatibility

By default, Dalli uses Marshal to encode values stored in memcached, which
Elixir can't understand. So you have to change the serializer to something like JSON:

Ruby
```ruby
client = Dalli::Client.new(
  ["host01:11211", "host2:11211"],
  serializer: JSON,
)
client.set("foo", 100)
```

Elixir
```elixir
{:ok, cluster} = Cream.Cluster.start_link(
  servers: ["host01:11211", "host2:11211"],
  memcachex: [coder: Memcache.Coder.JSON]
)
Cream.Cluster.get(cluster, "foo")
# => "100"
```

So now both Ruby and Elixir will read/write to the memcached cluster in JSON,
but still beware! There are some differences between how Ruby and Elixir parse
JSON. For example, if you write an integer with Ruby, Ruby will read an integer,
but Elixir will read a string.

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

## Instrumentation

Cream uses [Instrumentation](https://hexdocs.pm/instrumentation) for... well,
instrumentation. It's default logging is hooked into this package. You can do
your own logging (or instrumentation) very easily.

```elixir
config :my_app, MyCluster,
  log: false

Instrumentation.subscribe "cream", fn tag, payload ->
  Logger.debug("cream.#{tag} took #{payload[:duration]} ms")
end
```

## Running the tests

Test dependencies:
 * Docker
 * Docker Compose
 * Ruby
 * Bundler

Then run...
```
bundle install
docker-compose up -d
mix test

# Stop and clean up containers
docker-compose stop
docker-compose rm
```

## TODO

* Server weights
* Parallel memcached requests
