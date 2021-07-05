require "dalli"
require "json"

servers = [
  "localhost:11201",
  "localhost:11202",
  "localhost:11203"
]

client = Dalli::Client.new(servers, serializer: JSON)

100.times do |i|
  client.set("cream_ruby_test_key_#{i}", i)
  client.set("cream_json_test_key_#{i}", {value: i})
end