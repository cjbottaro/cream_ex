require IEx

defmodule CreamTest do
  use ExUnit.Case

  # import ExUnit.CaptureLog # Used to capture logging and assert against it.

  alias Test.Cluster

  setup do
    Cluster.flush
    :ok
  end

  test "set and get" do
    assert Cluster.get("name") == nil
    Cluster.set({"name", "Callie"})
    assert Cluster.get("name") == "Callie"
  end

  test "multi set / multi get" do
    assert Cluster.get(["foo", "bar"]) == %{}
    Cluster.set(%{"foo" => "oof", "bar" => "rab"})
    assert Cluster.get(["foo", "bar"]) == %{"foo" => "oof", "bar" => "rab"}
  end

  test "multi get with missing key" do
    assert Cluster.get(["foo", "bar"]) == %{}
    Cluster.set(%{"foo" => "oof", "bar" => "rab"})
    assert Cluster.get(["foo", "bar", "baz"]) == %{"foo" => "oof", "bar" => "rab"}
  end

  test "multi fetch with some missing keys" do
    keys = ["foo", "bar", "baz"]
    values = ["oof", "rab", "zab"]
    expected = Enum.zip(keys, values) |> Enum.into(%{})

    Cluster.set({"foo", "oof"})
    assert Cluster.get(keys) == %{"foo" => "oof"}

    results = Cluster.fetch keys, fn missing_keys ->
      assert missing_keys == ["bar", "baz"]
      Enum.map(missing_keys, &String.reverse/1)
    end

    assert results == expected
    assert Cluster.get(keys) == expected
  end

  test "multi fetch with no missing keys" do
    keys = ["foo", "bar", "baz"]
    values = ["oof", "rab", "zab"]
    expected = Enum.zip(keys, values) |> Enum.into(%{})

    Cluster.set(expected)
    assert Cluster.get(keys) == expected

    fetch_results = Cluster.fetch keys, fn _missing_keys ->
      assert false
      "this should not even be called"
    end

    assert fetch_results == expected
    assert Cluster.get(keys) == expected
  end

  test "single fetch" do
    assert Cluster.get("name") == nil
    assert Cluster.fetch("name", fn -> "Callie" end) == "Callie"
    assert Cluster.get("name") == "Callie"
  end

  test "single fetch when key exists" do
    Cluster.set {"name", "Callie"}
    assert Cluster.get("name") == "Callie"
    assert Cluster.fetch("name", fn -> "Not Callie" end) == "Callie"
    assert Cluster.get("name") == "Callie"
  end

end
