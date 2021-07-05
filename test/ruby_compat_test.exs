defmodule RubyCompatTest do
  use ExUnit.Case

  alias Cream.{Cluster, Coder}

  setup_all do
    cluster = Cluster.new(servers: [
      "localhost:11201",
      "localhost:11202",
      "localhost:11203"
    ])

    [cluster: cluster]
  end

  test "no coder", %{cluster: cluster} do
    Enum.each(1..99, fn i ->
      expected = to_string(i)
      {:ok, ^expected} = Cream.Cluster.get(cluster, "cream_ruby_test_key_#{i}")

      expected = Jason.encode!(%{value: i})
      {:ok, ^expected} = Cream.Cluster.get(cluster, "cream_json_test_key_#{i}")
    end)
  end

  test "jason coder", %{cluster: cluster} do
    Enum.each(1..99, fn i ->
      expected = i
      {:ok, ^expected} = Cream.Cluster.get(cluster, "cream_ruby_test_key_#{i}", coder: Coder.Jason)

      expected = %{"value" => i}
      {:ok, ^expected} = Cream.Cluster.get(cluster, "cream_json_test_key_#{i}", coder: Coder.Jason)
    end)
  end

end
