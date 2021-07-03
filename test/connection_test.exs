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

  test "set", %{conn: conn} do
    :ok = Connection.set(conn, {"foo", "bar"})
    {:ok, cas} = Connection.set(conn, {"foo", "bar"}, return_cas: true)
    {:error, :exists} = Connection.set(conn, {"foo", "bar1", cas: cas+1})
    {:ok, "bar"} = Connection.get(conn, "foo")
    :ok = Connection.set(conn, {"foo", "bar1", cas: cas})
    {:ok, "bar1"} = Connection.get(conn, "foo")
  end

  test "get", %{conn: conn} do
    :ok = Connection.set(conn, {"name", "Callie"})

    {:ok, nil} = Connection.get(conn, "foo")
    {:error, :not_found} = Connection.get(conn, "foo", verbose: true)
    {:ok, "Callie"} = Connection.get(conn, "name")
    {:ok, "Callie", cas} = Connection.get(conn, "name", return_cas: true)
    assert is_integer(cas)
  end

end
