defmodule Cream.Utils do

  def normalize_item(item, opts \\ [])

  def normalize_item({key, value}, opts) do
    ttl = Keyword.get(opts, :ttl, 0)
    {key, value, ttl, 0}
  end

  def normalize_item({key, value, item_opts}, opts) do
    ttl = item_opts[:ttl] || opts[:ttl] || 0
    cas = Keyword.get(item_opts, :cas, 0)
    {key, value, ttl, cas}
  end

end
