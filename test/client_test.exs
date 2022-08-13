defmodule ClientTest do
  use ExUnit.Case
  alias Cream.Error

  setup_all do
    {:ok, _client} = TestClient.start_link()
    :ok = TestClient.flush()
    {_, 0} = System.cmd("bundle", ["exec", "ruby", "test/support/populate.rb"])
    :ok
  end

  test "Config gets merged with use args" do
    config = TestClient.config()

    assert length(config[:servers]) == 3
    assert config[:coder] == Cream.Coder.Jason
  end

  test ":coder arg overrides config" do
    Enum.each(0..99, fn i ->
      expected = to_string(i)
      {:ok, ^expected} = TestClient.get("cream_ruby_test_key_#{i}", coder: false)

      expected = Jason.encode!(%{value: i})
      {:ok, ^expected} = TestClient.get("cream_json_test_key_#{i}", coder: false)
    end)
  end

  test "json coder" do
    Enum.each(0..99, fn i ->
      expected = i
      {:ok, ^expected} = TestClient.get("cream_ruby_test_key_#{i}")

      expected = %{"value" => i}
      {:ok, ^expected} = TestClient.get("cream_json_test_key_#{i}")
    end)
  end

  test "fetch" do
    :ok = TestClient.delete("foo")

    {:error, %Error{reason: :not_found}} = TestClient.get("foo", verbose: true)
    {:ok, "bar"} = TestClient.fetch("foo", fn -> "bar" end)
    {:ok, "bar"} = TestClient.get("foo")

    :ok = TestClient.set({"foo", "baz"})
    {:ok, "baz"} = TestClient.fetch("foo", fn -> "bar" end)
    {:ok, "baz"} = TestClient.get("foo")
  end

end
