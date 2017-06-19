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

20.times{ |i| client.set("cream_ruby_test_key_#{i}", i) }
