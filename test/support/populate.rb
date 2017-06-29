require "dalli"
require "json"

client = Dalli::Client.new(
  [
    "localhost:11201",
    "localhost:11202",
    "localhost:11203"
  ],
  serializer: JSON,
)

if ARGV[0] == "json"
  client.set "foo", {"one" => ["two", "three"]}
  exit(0)
end

20.times{ |i| client.set("cream_ruby_test_key_#{i}", i) }
