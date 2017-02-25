require IEx
defmodule Cream.Preload.BelongsTo do

  import Ecto.Query, only: [from: 2]

  def call(cluster, records, assoc, options \\ []) do
    repo = Repo # TODO

    # Make two lists in one pass. A list of keys and a list of {record, key}
    # tuples.
    {keys, records} = Enum.reduce records, {[], []}, fn record, {keys, records} ->
      key = key_from_source(record, assoc)
      keys = [key | keys]
      records = [{record, key} | records]
      {keys, records}
    end

    # Maintain same order as input so that our output is in the same order.
    records = Enum.reverse(records)

    attributes_by_key = Cream.fetch keys, fn missing ->

      ids = Enum.map missing, fn key ->
        String.split(key, ":")
          |> List.last
          |> String.to_integer
      end

      (from r in assoc.related, where: field(r, ^assoc.related_key) in ^ids)
        |> repo.all
        |> Enum.reduce(%{}, fn record, acc ->
          key = key_from_target(record, assoc)
          json = serialize(record)
          Map.put(acc, key, json)
        end)
    end

    Enum.map records, fn {record, key} ->
      if attributes = attributes_by_key[key] do
        %{ record | assoc.field => instantiate(assoc.related, attributes) }
      else
        record
      end
    end

  end

  defp fetch_ids(cluster, repo, keys) do
    Cream.fetch cluster, keys, fn missing ->

      ids = Enum.map keys, fn key ->
        [_, _, id | _] = String.split(key, ":")
        String.to_integer(id)
      end

      (from r in assoc.related, where: field(r, ^assoc.re))
    end
  end

  defp id_key_from_source(record, assoc) do
    id = Map.get(record, assoc.owner_key)
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
