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

  test "with conn" do

    keys = ~w(foo bar baz zip kip pik)

    results = keys
      |> Cluster.with_conn(fn conn, keys ->
        Enum.map(keys, &Memcache.get(conn, &1))
      end)
      |> Map.values
      |> List.flatten

    assert results == Enum.map(keys, fn _ -> {:error, "Key not found"} end)
  end

  test "Dalli compatibility" do
    {_, 0} = System.cmd("bundle", ~w(exec ruby test/support/populate.rb))

    expected_hits = (0..19)
      |> Enum.map(&{"cream_ruby_test_key_#{&1}", &1})
      |> Enum.into(%{})

    hits = expected_hits
      |> Map.keys
      |> Cluster.get

    assert hits == expected_hits
  end

  test "Dalli compatibility with JSON" do
    {_, 0} = System.cmd("bundle", ~w(exec ruby test/support/populate.rb json))

    expected = %{"one" => ["two", "three"]}
    actual = Cluster.get("foo")

    assert expected == actual
  end

  test "delete" do
    Cluster.set({"foo", "bar"})
    assert Cluster.get("foo") == "bar"
    Cluster.delete("foo")
    assert Cluster.get("foo") == nil
  end

  test "multi delete" do
    Cluster.set([{"foo", "bar"}, {"one", "two"}])
    assert Cluster.get("foo") == "bar"
    assert Cluster.get("one") == "two"
    Cluster.delete(["foo", "one"])
    assert Cluster.get("foo") == nil
    assert Cluster.get("one") == nil
  end

end
