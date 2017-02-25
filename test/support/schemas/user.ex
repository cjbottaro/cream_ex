defmodule User do
  use Ecto.Schema
  use Cream.Ecto

  schema "users" do
    field :name, :string, null: false
    has_one :email, Email
    has_many :posts, Post
    timestamps()
  end

  cream_preloadable [:email, :posts]
end
