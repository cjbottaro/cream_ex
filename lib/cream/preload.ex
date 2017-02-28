defmodule Cream.Preload do

  defmacro __using__(_) do
    quote do
      import Ecto.Query, only: [from: 2]
      import Cream.Preload, only: [instantiate: 4]
    end
  end

  def instantiate(schema, attributes, id, agent) do
    if record = Agent.get agent, &Map.get(&1, {schema,id}) do
      record
    else
      source = schema.__schema__(:source)
      prefix = schema.__schema__(:prefix)
      attributes = Poison.decode!(attributes)
      record = Ecto.Schema.__load__(schema, prefix, source, nil, attributes, &custom_loader(&1, &2))
      Agent.update agent, &Map.put(&1, {schema,id}, record)
      record
    end
  end

  defp custom_loader(_, nil), do: {:ok, nil}
  defp custom_loader(:utc_datetime, value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end
  defp custom_loader(:date, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> :error
    end
  end
  defp custom_loader(type, value) do
    Ecto.Type.adapter_load(Ecto.Adapters.Postgres, type, value)
  end

end
