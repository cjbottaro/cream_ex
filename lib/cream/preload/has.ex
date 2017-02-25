require IEx
defmodule Cream.Preload.Has do

  import Ecto.Query, only: [from: 2]

  def call(cluster, records, assoc, options \\ []) do
    repo = Repo # TODO

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
      |> Enum.reduce(%{}, fn {key, attributes}, acc ->
        record = instantiate(assoc.related, attributes)
        id = String.split(key, ":") |> List.last |> String.to_integer
        Map.put(acc, id, record)
      end)

    # Finally, add them into our original records.
    Enum.map records, fn {record, key} ->
      related_ids = related_ids_by_key[key]
      related_records = Enum.map(related_ids, &related_records_by_id[&1])
      if assoc.cardinality == :one do
        %{ record | assoc.field => List.first(related_records) }
      else
        %{ record | assoc.field => related_records }
      end
    end

  end

  defp fetch_ids(cluster, repo, assoc, keys) do
    Cream.fetch cluster, keys, fn missing ->

      ids = Enum.map keys, fn key ->
        [_, _, id | _] = String.split(key, ":")
        String.to_integer(id)
      end

      query = from r in assoc.related,
        select: map(r, [:id, assoc.related_key]),
        where: field(r, ^assoc.related_key) in ^ids

      Enum.reduce(repo.all(query), %{}, fn record, acc ->
        id_key = id_key_from_target(record, assoc)
        if list = acc[id_key] do
          Map.put(acc, id_key, [record.id | list])
        else
          Map.put(acc, id_key, [record.id])
        end
      end) |> Enum.map(fn {key, ids} ->
        {key, Poison.encode!(ids)}
      end)

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

  defp instantiate(schema, attributes) do
    fields = schema.__schema__(:fields)
    changeset = Ecto.Changeset.cast(
      struct!(schema),
      Poison.decode!(attributes),
      fields
    )
    record = struct!(schema, changeset.changes)
    put_in(record.__meta__.state, :loaded)
  end

end
