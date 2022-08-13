require "dalli"
require "json"

containers = JSON.parse(`docker compose ps --format json`)
servers = containers.sort_by{ |c| c["Name"] }.map do |c|
  port = c["Publishers"][0]["PublishedPort"]
  "localhost:#{port}"
end

client = Dalli::Client.new(servers, serializer: JSON)

100.times do |i|
  client.set("cream_ruby_test_key_#{i}", i)
  client.set("cream_json_test_key_#{i}", {value: i})
end