defmodule Cream.Instrumentation do
  @moduledoc false

  def instrument(tag, opts \\ [], f) do
    Instrumentation.instrument "cream", tag, fn ->
      f.() |> payload(tag, Map.new(opts))
    end
  end

  defp payload(results, "set", %{items: items}) do
    keys = Enum.map(items, fn {k, _} -> k end)
    {results, [keys: keys]}
  end

  defp payload(results, "get", %{keys: keys}) do
    misses = Enum.reject(keys, fn key -> Map.has_key?(results, key) end)
    {results, keys: keys, misses: misses}
  end

  defp payload(wrapped, "fetch", %{key: key}) do
    case wrapped do
      {results, :hit}  -> {results, keys: [key], misses: []}
      {results, :miss} -> {results, keys: [key], misses: [key]}
    end
  end

  defp payload(wrapped, "fetch", %{keys: keys}) do
    {results, misses} = wrapped
    {results, keys: keys, misses: misses}
  end

  defp payload(results, "delete", %{keys: keys}) do
    misses = Enum.filter(keys, fn key ->
      case results[key] do
        {:error, _} -> true
        _ -> false
      end
    end)
    {results, keys: keys, misses: misses}
  end

  defp payload(results, "flush", %{}) do
    {successes, failures} = Enum.reduce(results, {0,0}, fn result, {s, f} ->
      case result do
        :ok -> {s+1, f}
        _ -> {s, f+1}
      end
    end)

    {results, [successes: successes, failures: failures]}
  end

end
