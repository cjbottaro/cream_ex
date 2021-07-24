defmodule ClientTest do
  use ExUnit.Case

  setup_all do
    {:ok, _client} = TestClient.start_link()
    :ok
  end

  test "Config gets merged with use args" do
    config = TestClient.config()

    assert config[:servers] == ~w(localhost:11201 localhost:11202 localhost:11203)
    assert config[:coder] == Cream.Coder.Jason
  end

  test ":coder arg overrides config" do
    Enum.each(0..99, fn i ->
      expected = to_string(i)
      {:ok, ^expected} = TestClient.get("cream_ruby_test_key_#{i}", coder: nil)

      expected = Jason.encode!(%{value: i})
      {:ok, ^expected} = TestClient.get("cream_json_test_key_#{i}", coder: nil)
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

end
