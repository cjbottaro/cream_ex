defmodule ConnectionTest do
  use ExUnit.Case
  # doctest Cream.Connection, import: true, only: [set: 3]

  alias Cream.{Connection, Error, Coder}

  setup_all do
    {:ok, conn} = Connection.start_link()
    [conn: conn]
  end

  setup %{conn: conn} do
    :ok = Connection.flush(conn)
  end

  test "set", %{conn: conn} do
    :ok = Connection.set(conn, {"foo", "bar"})
    {:ok, cas} = Connection.set(conn, {"foo", "bar"}, cas: true)
    {:error, %Error{reason: :exists}} = Connection.set(conn, {"foo", "bar1", cas: cas+1})
    {:ok, "bar"} = Connection.get(conn, "foo")
    :ok = Connection.set(conn, {"foo", "bar1", cas: cas})
    {:ok, "bar1"} = Connection.get(conn, "foo")
  end

  test "get", %{conn: conn} do
    {:ok, set_cas} = Connection.set(conn, {"name", "Callie"}, cas: true)

    {:ok, nil} = Connection.get(conn, "foo")
    {:error, %Error{reason: :not_found}} = Connection.get(conn, "foo", verbose: true)
    {:ok, "Callie"} = Connection.get(conn, "name")
    {:ok, "Callie", get_cas} = Connection.get(conn, "name", cas: true)
    assert set_cas == get_cas
  end

  test "delete", %{conn: conn} do
    {:error, %Error{reason: :not_found}} = Connection.delete(conn, "foo", verbose: true)
    :ok = Connection.delete(conn, "foo")

    :ok = Connection.set(conn, {"foo", "bar"})
    {:ok, "bar"} = Connection.get(conn, "foo")
    :ok = Connection.delete(conn, "foo", verbose: true)
    {:error, %Error{reason: :not_found}} = Connection.get(conn, "foo", verbose: true)
    {:error, %Error{reason: :not_found}} = Connection.delete(conn, "foo", verbose: true)

    :ok = Connection.set(conn, {"foo", "bar"})
    {:ok, "bar"} = Connection.get(conn, "foo")
    :ok = Connection.delete(conn, "foo")
    {:error, %Error{reason: :not_found}} = Connection.get(conn, "foo", verbose: true)
    {:error, %Error{reason: :not_found}} = Connection.delete(conn, "foo", verbose: true)
  end

  test "fetch", %{conn: conn} do
    {:error, %Error{reason: :not_found}} = Connection.get(conn, "foo", verbose: true)
    {:ok, "bar"} = Connection.fetch(conn, "foo", fn -> "bar" end)
    {:ok, "bar"} = Connection.get(conn, "foo")

    :ok = Connection.set(conn, {"foo", "baz"})
    {:ok, "baz"} = Connection.fetch(conn, "foo", fn -> "bar" end)
    {:ok, "baz"} = Connection.get(conn, "foo")
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

  test "override coder" do
    value = %{"a" => "b"}
    {:ok, conn} = Connection.start_link(coder: Coder.Jason)

    :ok = Connection.set(conn, {"foo", value})
    :ok = Connection.set(conn, {"bar", value}, coder: [Coder.Jason, Coder.Gzip])

    {:ok, foo} = Connection.get(conn, "foo", coder: false)
    {:ok, bar} = Connection.get(conn, "bar", coder: false)

    assert is_binary(foo)
    assert is_binary(bar)

    assert foo != value
    assert bar != value

    assert Jason.decode!(foo) == value

    assert :zlib.gunzip(bar) != value
    assert :zlib.gunzip(bar) |> Jason.decode!() == value
  end

end
