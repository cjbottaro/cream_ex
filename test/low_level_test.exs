defmodule LowLevelTest do
  use ExUnit.Case

  alias Cream.{Connection, Packet}

  setup_all do
    {:ok, conn} = Connection.start_link()
    [conn: conn]
  end

  test "noop", %{conn: conn} do
    :ok = Connection.send_packets(conn, [Packet.new(:noop)])
    {:ok, [%{opcode: :noop}]} = Connection.recv_packets(conn, 1)
  end

  test "flush", %{conn: conn} do
    :ok = Connection.send_packets(conn, [Packet.new(:flush)])
    {:ok, [%{opcode: :flush}]} = Connection.recv_packets(conn, 1)
  end

  describe "set, add, replace" do

    setup :flush

    test "set", %{conn: conn} do
      :ok = Connection.send_packets(conn, [Packet.new(:set, key: "foo", value: "bar")])
      {:ok, [packet]} = Connection.recv_packets(conn, 1)

      assert packet.opcode == :set
      assert packet.status == :ok
    end

    test "setq", %{conn: conn} do
      :ok = Connection.send_packets(conn, [
        Packet.new(:setq, key: "foo", value: "bar"),
        Packet.new(:set, key: "bar", value: "foo"),
      ])
      {:ok, [packet]} = Connection.recv_packets(conn, 1)

      assert packet.opcode == :set
      assert packet.status == :ok
    end

  end

  describe "retrieving (misses)" do

    setup :flush

    test "get", %{conn: conn} do
      :ok = Connection.send_packets(conn, [Packet.new(:get, key: "foo")])
      {:ok, [packet]} = Connection.recv_packets(conn, 1)

      assert packet.opcode == :get
      assert packet.status == :not_found
      assert packet.key    == ""
      assert packet.value  == "Not found"
    end

    test "getk", %{conn: conn} do
      :ok = Connection.send_packets(conn, [Packet.new(:getk, key: "foo")])
      {:ok, [packet]} = Connection.recv_packets(conn, 1)

      assert packet.opcode == :getk
      assert packet.status == :not_found
      assert packet.key    == "foo"
      assert packet.value  == ""
    end

    test "getq", %{conn: conn} do
      :ok = Connection.send_packets(conn, [
        Packet.new(:getq, key: "foo"),
        Packet.new(:getk, key: "bar")
      ])
      {:ok, [packet]} = Connection.recv_packets(conn, 1)

      assert packet.opcode == :getk
      assert packet.status == :not_found
      assert packet.key    == "bar"
      assert packet.value  == ""
    end

    test "getqk", %{conn: conn} do
      :ok = Connection.send_packets(conn, [
        Packet.new(:getkq, key: "foo"),
        Packet.new(:getk, key: "bar")
      ])
      {:ok, [packet]} = Connection.recv_packets(conn, 1)

      assert packet.opcode == :getk
      assert packet.status == :not_found
      assert packet.key    == "bar"
      assert packet.value  == ""
    end

  end

  describe "retrieving (hits)" do

    setup :flush

    setup %{conn: conn} do
      :ok = Connection.send_packets(conn, [Packet.new(:set, key: "foo", value: "bar")])
      {:ok, [%{opcode: :set}]} = Connection.recv_packets(conn, 1)
      [conn: conn]
    end

    test "get", %{conn: conn} do
      :ok = Connection.send_packets(conn, [Packet.new(:get, key: "foo")])
      {:ok, [packet]} = Connection.recv_packets(conn, 1)

      assert packet.opcode == :get
      assert packet.status == :ok
      assert packet.key    == ""
      assert packet.value  == "bar"
    end

    test "getq", %{conn: conn} do
      :ok = Connection.send_packets(conn, [
        Packet.new(:getq, key: "baz"),
        Packet.new(:getq, key: "foo")
      ])
      {:ok, [packet]} = Connection.recv_packets(conn, 1)

      assert packet.opcode == :getq
      assert packet.status == :ok
      assert packet.key    == ""
      assert packet.value  == "bar"
    end

    test "getk", %{conn: conn} do
      :ok = Connection.send_packets(conn, [Packet.new(:getk, key: "foo")])
      {:ok, [packet]} = Connection.recv_packets(conn, 1)

      assert packet.opcode == :getk
      assert packet.status == :ok
      assert packet.key    == "foo"
      assert packet.value  == "bar"
    end

    test "getkq", %{conn: conn} do
      :ok = Connection.send_packets(conn, [
        Packet.new(:getkq, key: "baz"),
        Packet.new(:getkq, key: "foo")
      ])
      {:ok, [packet]} = Connection.recv_packets(conn, 1)

      assert packet.opcode == :getkq
      assert packet.status == :ok
      assert packet.key    == "foo"
      assert packet.value  == "bar"
    end

  end

  describe "extras (flags)" do
    setup :flush

    test "set", %{conn: conn} do
      :ok = Connection.send_packets(conn, [
        Packet.new(:set, key: "foo", value: "bar", flags: 123),
        Packet.new(:get, key: "foo")
      ])
      {:ok, [_, packet]} = Connection.recv_packets(conn, 2)

      assert packet.opcode == :get
      assert packet.status == :ok
      assert packet.value  == "bar"
      assert packet.extra.flags == 123
    end

  end

  def flush(%{conn: conn}) do
    :ok = Connection.send_packets(conn, [Packet.new(:flush)])
    {:ok, [%{opcode: :flush}]} = Connection.recv_packets(conn, 1)
    :ok
  end

end
