defmodule TestClient do
  use Cream.Client, servers: [
    "localhost:11201",
    "localhost:11202",
    "localhost:11203"
  ]
end
