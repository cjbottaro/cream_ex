defmodule ConnectionTest do
  use ExUnit.Case

  alias Cream.{Connection, Coder}

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

  # Note that this uses Cream.Coder.Json which is different from
  # Cream.Coder.Jason and only exists in test env.
  test "single coder", %{conn: conn} do
    coder = Coder.Json
    map = %{"a" => "b"}
    json = ~S({"a":"b"})

    # Encode maps.
    :ok = Connection.set(conn, {"foo", map}, coder: coder)
    {:ok, ^map} = Connection.get(conn, "foo", coder: coder)
    {:ok, ^json} = Connection.get(conn, "foo")

    # Doesn't encode binaries.
    :ok = Connection.set(conn, {"foo", json}, coder: coder)
    {:ok, ^json} = Connection.get(conn, "foo", coder: coder)
    {:ok, ^json} = Connection.get(conn, "foo")
  end

  test "double coder", %{conn: conn} do
    coder = [Coder.Jason, Coder.Gzip]
    map = %{"a" => "b"}

    :ok = Connection.set(conn, {"foo", map}, coder: coder)
    {:ok, ^map} = Connection.get(conn, "foo", coder: coder)

    {:ok, data} = Connection.get(conn, "foo")
    {:ok, ^map} = :zlib.gunzip(data) |> Jason.decode()
  end

end
