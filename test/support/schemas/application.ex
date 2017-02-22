defmodule Orm.Application do
  use Ecto.Schema

  schema "applications" do
    belongs_to :user, Orm.User
  end

end
