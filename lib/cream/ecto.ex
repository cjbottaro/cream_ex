defmodule Cream.Ecto do

  defmacro __using__(_) do
    quote do
      import Cream.Ecto
      Module.register_attribute __MODULE__, :cream_associations, accumulate: true, persist: true
    end
  end

  defmacro cream_preloadable(association_names) do
    quote do: @cream_associations unquote(association_names)
  end

end
