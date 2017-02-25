defmodule Email do
  use Ecto.Schema

  schema "emails" do
    field :address, :string, null: false
    belongs_to :user, User
    timestamps()
  end
end
