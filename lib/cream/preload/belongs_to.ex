require IEx
require Logger
defmodule Cream.Preload.BelongsTo do
  use Cream.Preload

  def call(cluster, records, assoc, options \\ []) do
    repo = Repo # TODO
    agent = Keyword.get(options, :agent)
    source_cache = %{}

    t1 = :os.system_time(:millisecond)
    # Make two lists in one pass. A list of keys and a list of {record, key}
    # tuples.
    {keys, records} = Enum.reduce records, {[], []}, fn record, {keys, records} ->
      key = key_from_source(record, assoc)
      keys = [key | keys]
      records = [{record, key} | records]
      {keys, records}
    end

    time = :os.system_time(:millisecond) - t1
    Logger.debug "#{inspect __MODULE__ } :#{assoc.field} setup #{length(records)} records #{time}ms"

    t1 = :os.system_time(:millisecond)
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
    time = :os.system_time(:millisecond) - t1
    Logger.debug "#{inspect __MODULE__ } :#{assoc.field} fetching #{length(records)} records #{time}ms"


    t1 = :os.system_time(:millisecond)
    # This reduce will reverse the order of the records which was reversed
    # already, thus we maintain original order!
    result = Enum.reduce records, {[], %{}}, fn {record, key}, {records, cache} ->
      cond do
        cache_hit = cache[{record.__struct__, record.id}] ->
          records = [cache_hit | records]
          {records, cache}
        attributes = attributes_by_key[key] ->
          id = Map.get(record, assoc.owner_key)
          related_record = instantiate(assoc.related, attributes, id, agent)
          record = %{ record | assoc.field => related_record }
          records = [record | records]
          cache = Map.put cache, {record.__struct__, record.id}, record
          {records, cache}
        true ->
          cache = Map.put cache, {record.__struct__, record.id}, record
          records = [record | records]
          {records, cache}
      end
    end
    time = :os.system_time(:millisecond) - t1
    Logger.debug "#{inspect __MODULE__ } :#{assoc.field} updating #{length(records)} records #{time}ms, hits: #{Map.size(result |> elem(1))}"
    result |> elem(0)

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

end
