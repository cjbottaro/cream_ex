defmodule Cream.Preload do

  def call(records, association_name) do

    specs = Enum.map records, fn record ->
      association = association(record, association_name)
      assert_preloadable!(association)
      two_phased? = two_phased?(association)
      %{
        record: record,
        association: association,
        two_phased?: two_phased?,
        key: key_for(record, association, two_phased?)
      }
    end


  end

  defp association(record, name) do
    record.__struct__.__schema__(:association, name)
  end

  defp assert_preloadable!(association) do
    if two_phased?(association) do
      preloadable = association.owner.module_info(:attributes)[:cream_associations] || []
      if !Enum.member?(preloadable, association.field) do
        raise ArgumentError, "#{inspect association.field} on #{inspect association.owner} has not been declared to work with Cream.preload"
      end
    end
  end

  defp two_phased?(%Ecto.Association.BelongsTo{}), do: false
  defp two_phased?(%Ecto.Association.Has{cardinality: :many}), do: true
  defp two_phased?(%Ecto.Association.Has{cardinality: :one}), do: true

  defp key_for(record, association, false) do
    id = Map.get(record, association.owner_key) # Post.user_id
    "cream:#{inspect association.related}:#{id}"
  end

  defp key_for(record, association, true) do
    id = Map.get(record, association.owner_key) # Post.id
    "cream:#{inspect association.owner}:#{association.field}:ids"
  end

end
