defmodule Cream.Preload.Initializer do

  def run, do: run(preloadable_modules())
  def run([]), do: nil
  def run(modules) do
    :ets.new(Cream.Invalidations, [:named_table, :bag])

    Enum.each modules, fn module ->
      Enum.each module.module_info(:attributes)[:cream_associations], fn assoc_name ->
        assoc = module.__schema__(:association, assoc_name)
        template = {"cream:#{inspect module}:%d:#{assoc.field}:ids", assoc.related_key}
        :ets.insert(Cream.Invalidations, {assoc.related, template})
      end
    end
  end

  def applications_to_scan do
    case Application.get_env(:cream, :enable_preload, false) do
      true -> all_applications()
      false -> []
      list -> list
    end
  end

  def all_applications do
    Enum.map :application.loaded_applications(), fn {app, _, _} -> app end
  end

  def preloadable_modules do
    Enum.reduce applications_to_scan(), [], fn app, acc ->
      {:ok, modules} = :application.get_key(app, :modules)
      Enum.reduce modules, acc, fn mod, acc ->
        if has_associations?(mod) do
          [mod | acc]
        else
          acc
        end
      end
    end
  end

  defp has_associations?(mod) do
    assocs = mod.module_info(:attributes)[:cream_associations]
    assocs && is_list(assocs) && length(assocs) > 0
  end

end
