defmodule Cream.ConnectionPool do
  use GenServer

  def start_link(options \\ [], gen_options \\ [], func) do
    options = Keyword.merge [size: 10], options
    GenServer.start_link(__MODULE__, {func, options}, gen_options)
  end

  def checkout(pid), do: GenServer.call(pid, :checkout)

  def checkin(pid, conn), do: GenServer.call(pid, {:checkin, conn})

  def with(pid, func) do
    conn = checkout(pid)
    try do
      func.(conn)
    after
      checkin(pid, conn)
    end
  end

  def init({func, options}) do
    size = Keyword.fetch!(options, :size)

    {:ok, %{func: func, size: size, ready: [], in_use: [], waiters: []}}
  end

  def handle_call(:checkout, from, state) do
    %{ ready: ready, in_use: in_use, size: size, func: func, waiters: waiters } = state

    cond do
      length(ready) > 0 ->
        [conn | rest] = ready
        state = %{ state | ready: rest, in_use: [conn | in_use]}
        {:reply, conn, state}
      length(ready) + length(in_use) < size ->
        conn = func.()
        state = %{ state | in_use: [conn | in_use] }
        {:reply, conn, state}
      true ->
        {:noreply, %{state | waiters: [from | waiters]}}
    end
  end

  def handle_call({:checkin, conn}, _from, state) do
    %{ ready: ready, in_use: in_use } = state
    in_use = List.delete(in_use, conn)
    ready = [conn | ready]
    {:reply, :ok, %{state | in_use: in_use, ready: ready}}
  end

  def handle_call(:debug, _from, state), do: {:reply, state, state}

end
