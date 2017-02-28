defmodule Cream do

  require Logger
  alias Cream.{Command}

  def new(options \\ []), do: Cream.Cluster.new(options)

  defdelegate flush(pool_or_cluster \\ :__default__, options \\ []), to: Command.Flush
  defdelegate fetch(pool_or_cluster \\ :__default__, keys, func), to: Command.Fetch
  defdelegate set(pool_or_cluster \\ :__default__, keys_and_values), to: Command.Set
  defdelegate get(pool_or_cluster \\ :__default__, keys), to: Command.Get

  def preload(cluster \\ :__default__, records, assoc_name, options \\ [])

  def preload(cluster, records, assoc_name, options = []) do
    {:ok, agent} = Agent.start_link(fn -> %{} end)
    try do
      preload(cluster, records, assoc_name, Keyword.put(options, :agent, agent))
    after
      Agent.stop(agent)
    end
  end

  def preload(cluster, records, assoc_name, options) when is_atom(assoc_name) do
    t1 = :os.system_time(:millisecond)
    assoc = List.first(records).__struct__.__schema__(:association, assoc_name)
    result = case assoc do
      %Ecto.Association.BelongsTo{} ->
        Cream.Preload.BelongsTo.call(cluster, records, assoc, options)
      %Ecto.Association.Has{} ->
        Cream.Preload.Has.call(cluster, records, assoc, options)
    end
    time = :os.system_time(:millisecond) - t1
    Logger.debug "Cream.preload #{inspect assoc_name} #{time}ms"
    result
  end

  def preload(cluster, records, assoc_names, options) when is_list(assoc_names) do
    Enum.reduce assoc_names, records, fn assoc_name, acc ->
      preload(cluster, acc, assoc_name, options)
    end
  end

  def preload(cluster, records, assoc_names, options) when is_tuple(assoc_names) do
    {assoc_name1, assoc_name2} = assoc_names

    Logger.warn "assoc1: #{assoc_name1} #{length(records)}"
    records = preload(cluster, records, assoc_name1, options)
    # if assoc_name1 == :opportunity do
    #   require IEx
    #   IEx.pry
    # end
    Logger.warn "assoc1: #{assoc_name1} #{length(records)}"


    # Extract out the associated records we preloaded.
    next_records = Enum.map(records, &Map.get(&1, assoc_name1))
      |> List.flatten

    # Send them to be preloaded with the next assoc.
    Logger.warn "assoc2: #{inspect assoc_name2} #{length(next_records)}"
    next_records = preload(cluster, next_records, assoc_name2, options)
    Logger.warn "assoc2: #{inspect assoc_name2} #{length(next_records)}"

    # Index them by primary key.
    next_records = Enum.reduce next_records, %{}, fn record, acc ->
      Map.put(acc, record.id, record)
    end

    # Now replace our preloaded associated records with the
    # preloaded versions of themselves.
    Enum.map records, fn record ->
      related_records = case Map.get(record, assoc_name1) do
        records when is_list(records) ->
          Enum.map(records, &next_records[&1.id]) # TODO don't hardcode id
        record ->
          next_records[record.id]
      end

      Map.put(record, assoc_name1, related_records)
    end

  end

end
