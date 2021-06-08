defmodule ConnectionTest do
  use ExUnit.Case

  alias Cream.Connection

  setup_all do
    {:ok, conn} = Connection.start_link()
    [conn: conn]
  end

  setup %{conn: conn} do
    :ok = Connection.flush(conn)
  end

  test "set/get", %{conn: conn} do
    {:error, :not_found} = Connection.get(conn, "foo")
    {:error, :not_found} = Connection.get(conn, "foo", cas: true)

    :ok = Connection.set(conn, {"foo", "bar"})

    {:ok, "bar"} = Connection.get(conn, "foo")
    {:ok, {"bar", cas}} = Connection.get(conn, "foo", cas: true)

    {:error, :exists} = Connection.set(conn, {"foo", "baz", cas: cas-1})
    {:ok, "bar"} = Connection.get(conn, "foo")
    :ok = Connection.set(conn, {"foo", "baz", cas: cas})
    {:ok, "baz"} = Connection.get(conn, "foo")
  end

  test "mset/mget", %{conn: conn} do
    :ok = Connection.set(conn, {"foo", "bar"})

    {:ok, results} = Connection.mget(conn, ["foo", "bar"])
    assert results == [{:ok, "bar"}, {:error, :not_found}]

    {:ok, results} = Connection.mget(conn, ["foo", "bar"], cas: true)
    [{:ok, {"bar", cas}}, {:error, :not_found}] = results
    assert is_integer(cas)

    :ok = Connection.set(conn, {"bar", "foo"})

    {:ok, results} = Connection.mget(conn, ["foo", "bar"])
    assert results == [{:ok, "bar"}, {:ok, "foo"}]

    {:ok, results} = Connection.mget(conn, ["foo", "bar"], cas: true)
    [{:ok, {"bar", cas1}}, {:ok, {"foo", cas2}}] = results
    assert is_integer(cas1) and is_integer(cas2)

    {:ok, results} = Connection.mset(conn, [
      {"foo", "bar2", cas: cas1+1},
      {"bar", "foo2", cas: cas2},
    ])

    assert results == [{:error, :exists}, :ok]

    {:ok, results} = Connection.mget(conn, ["foo", "bar"])
    assert results == [{:ok, "bar"}, {:ok, "foo2"}]

    {:ok, results} = Connection.mget(conn, ["foo", "bar"], cas: true)
    [{:ok, {"bar", foo_cas}}, {:ok, {"foo2", bar_cas}}] = results

    {:ok, results} = Connection.mset(conn, [
      {"foo", "bar2", cas: foo_cas+1},
      {"bar", "foo3", cas: bar_cas},
    ], cas: true)
    [{:error, :exists}, {:ok, bar_cas}] = results
    assert is_integer(bar_cas)
  end

end
