# Maybe needed if we ever implement mset/mget, but maybe not.
# Instead of MultiError, we could just reduce_while until we
# hit the first error and just return that.
defmodule Cream.MultiError do
  @moduledoc false
  defexception [:message]
end
