# Cache. Rules. Everything. Around. Me.

A Dalli compatible memcached client.

It uses the same consistent hashing algorithm as Dalli to determine which server
a key is on.

## Quickstart

Sensible defaults...

```
iex(1)> {:ok, client} = Cream.Client.start_link()
{:ok, #PID<0.265.0>}

iex(1)> Cream.Client.set(client, {"foo", "bar"})
:ok

iex(1)> Cream.Client.get(client, "foo")
{:ok, "bar"}
```

As a module with custom config...

```
import Config

config MyClient, servers: ["memcached01:11211", "memcached02:11211"]

def MyClient do
  use Cream.Client
end

iex(1)> {:ok, _client} = MyClient.start_link()
{:ok, #PID<0.265.0>}

iex(1)> MyClient.set({"foo", "bar"})
:ok

iex(1)> MyClient.get(client, "foo")
{:ok, "bar"}
```

## Running the tests

Test dependencies:
 * Docker
 * Docker Compose
 * Ruby
 * Bundler

Then run...
```sh
docker-compose up -d
bundle install --path vendor/bundle
bundle exec ruby test/support/populate.rb

mix test

# Stop and clean up containers
docker-compose stop
docker-compose rm
```

## Todo

* Server weights
* Parallel memcached requests
