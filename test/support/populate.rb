require "dalli"
require "json"

puts ARGV.inspect

client = Dalli::Client.new(ARGV.to_a, serializer: JSON)

100.times do |i|
  client.set("cream_ruby_test_key_#{i}", i)
  client.set("cream_json_test_key_#{i}", {value: i})
end