defmodule ConnectionTest do
  use ExUnit.Case

  alias Cream.Connection

  setup_all do
    {:ok, conn} = Connection.start_link()
    [conn: conn]
  end

  setup %{conn: conn} do
    :ok = Connection.flush(conn)
    :ok = Connection.set(conn, {"name", "Callie"})
  end

  test "set", %{conn: conn} do
    :ok = Connection.set(conn, {"foo", "bar"})
    {:ok, cas} = Connection.set(conn, {"foo", "bar"}, cas: true)
    {:error, :exists} = Connection.set(conn, {"foo", "bar1", cas: cas+1})
    {:ok, "bar"} = Connection.get(conn, "foo")
    :ok = Connection.set(conn, {"foo", "bar1", cas: cas})
    {:ok, "bar1"} = Connection.get(conn, "foo")
  end

  test "get", %{conn: conn} do
    {:ok, nil} = Connection.get(conn, "foo")
    {:error, :not_found} = Connection.get(conn, "foo", verbose: true)
    {:ok, "Callie"} = Connection.get(conn, "name")
    {:ok, {"Callie", cas}} = Connection.get(conn, "name", cas: true)
    assert is_integer(cas)
  end

  test "mset", %{conn: conn} do
    :ok = Connection.mset(conn, [
      {"foo", "bar"},
      {"name", "Genevieve"}
    ])

    {:ok, "bar"} = Connection.get(conn, "foo")
    {:ok, "Genevieve"} = Connection.get(conn, "name")

    {:ok, [ok: foo_cas, ok: name_cas]} = Connection.mset(conn, [
      {"foo", "bar"},
      {"name", "Genevieve"}
    ], cas: true)

    {:ok, [{:error, :exists}, :ok]} = Connection.mset(conn, [
      {"foo", "bar", cas: foo_cas+1},
      {"name", "Callie", cas: name_cas}
    ])
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
