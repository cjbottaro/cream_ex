require IEx
require Logger
defmodule Cream.Preload.Has do
  use Cream.Preload

  def call(cluster, records, assoc, options \\ []) do
    repo = Repo # TODO
    agent = options[:agent]

    # Make two lists in one pass. A list of keys and a list of {record, key}
    # tuples.
    {keys, records} = Enum.reduce records, {[], []}, fn record, {keys, records} ->
      key = id_key_from_source(record, assoc)
      keys = [key | keys]
      records = [{record, key} | records]
      {keys, records}
    end

    # Maintain same order as input so that our output is in the same order.
    records = Enum.reverse(records)

    # Convert %{ key => json_string } to %{ key => list[int] }
    related_ids_by_key = fetch_ids(cluster, repo, assoc, keys)
      |> Enum.reduce(%{}, fn {key, related_ids}, acc ->
        Map.put(acc, key, Poison.decode!(related_ids))
      end)

    # From %{ key => list[int] } to list[related_key]
    related_keys = Map.values(related_ids_by_key)
      |> List.flatten
      |> Enum.map(&key_from_id(&1, assoc))

    # %{ "cream:Comment:123" => json } to %{ 123 => %Comment{...} }
    related_records_by_id = fetch_attributes(cluster, repo, assoc, related_keys)

    t1 = :os.system_time(:millisecond)
    related_records_by_id = Enum.reduce(related_records_by_id, %{}, fn {key, attributes}, acc ->
        id = String.split(key, ":") |> List.last |> String.to_integer
        record = instantiate(assoc.related, attributes, id, agent)
        Map.put(acc, id, record)
      end)
    time = :os.system_time(:millisecond) - t1
    Logger.debug "#{inspect __MODULE__ } :#{assoc.field} updating #{length(records)} records #{time}ms"

    # Finally, add them into our original records.
    Enum.map records, fn {record, key} ->
      related_ids = related_ids_by_key[key]
      related_records = if related_ids do
        Enum.map(related_ids, &related_records_by_id[&1])
      else
        []
      end
      if assoc.cardinality == :one do
        %{ record | assoc.field => List.first(related_records) }
      else
        %{ record | assoc.field => related_records }
      end
    end

  end

  defp fetch_ids(cluster, repo, assoc, keys) do
    Cream.fetch cluster, keys, fn missing ->

      ids_and_keys = Enum.reduce keys, %{}, fn key, acc ->
        [_, _, id | _] = String.split(key, ":")
        Map.put(acc, String.to_integer(id), key)
      end

      query = from r in assoc.related,
        select: map(r, [:id, assoc.related_key]),
        where: field(r, ^assoc.related_key) in ^Map.keys(ids_and_keys)

      grouped_ids = Enum.reduce repo.all(query), %{}, fn record, acc ->
        fkey = Map.get(record, assoc.related_key)
        ids = Map.get(acc, fkey, [])
        Map.put(acc, fkey, [record.id | ids])
      end

      Enum.map ids_and_keys, fn {id, key} ->
        ids = grouped_ids[id] || []
        {key, Poison.encode!(ids)}
      end
    end
  end

  defp fetch_attributes(cluster, repo, assoc, keys) do
    Cream.fetch keys, fn missing ->

      ids = Enum.map missing, fn key ->
        String.split(key, ":")
          |> List.last
          |> String.to_integer
      end

      # TODO Don't hard code :id
      (from r in assoc.related, where: field(r, :id) in ^ids)
        |> repo.all
        |> Enum.reduce(%{}, fn record, acc ->
          key = key_from_id(record.id, assoc)
          json = serialize(record)
          Map.put(acc, key, json)
        end)

    end
  end

  defp id_key_from_source(record, assoc) do
    id = Map.get(record, assoc.owner_key)
    "cream:#{inspect assoc.owner}:#{id}:#{assoc.field}:ids"
  end

  defp id_key_from_target(record, assoc) do
    id = Map.get(record, assoc.related_key)
    "cream:#{inspect assoc.owner}:#{id}:#{assoc.field}:ids"
  end

  defp key_from_source(record, assoc) do
    id = Map.get(record, assoc.owner_key)
    "cream:#{inspect assoc.related}:#{id}"
  end

  defp key_from_target(record, assoc) do
    id = Map.get(record, assoc.related_key)
    "cream:#{inspect assoc.related}:#{id}"
  end

  defp key_from_id(id, assoc) do
    "cream:#{inspect assoc.related}:#{id}"
  end

  defp serialize(record) do
    fields = record.__struct__.__schema__(:fields)
    Enum.reduce(fields, %{}, fn key, acc ->
      value = Map.get(record, key)
      Map.put(acc, key, value)
    end) |> Poison.encode!
  end

end
