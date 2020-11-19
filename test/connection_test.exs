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
    nil = Connection.get(conn, "foo")
    nil = Connection.get(conn, "foo", cas: true)

    :ok = Connection.set(conn, {"foo", "bar"})

    {:ok, "bar"} = Connection.get(conn, "foo")
    {:ok, {"bar", cas}} = Connection.get(conn, "foo", cas: true)

    :exists = Connection.set(conn, {"foo", "baz", cas-1})
    {:ok, "bar"} = Connection.get(conn, "foo")
    :ok = Connection.set(conn, {"foo", "baz", cas})
    {:ok, "baz"} = Connection.get(conn, "foo")
  end

  test "mset/mget", %{conn: conn} do
    :ok = Connection.set(conn, {"foo", "bar"})

    Connection.mget(conn, ["foo", "bar"])
  end

end
