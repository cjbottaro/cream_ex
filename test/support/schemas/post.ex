defmodule Post do
  use Ecto.Schema
  use Cream.Ecto

  schema "posts" do
    field :title, :string, null: false
    belongs_to :user, User
    has_many :comments, Comment
    timestamps()
  end

  cream_preloadable [:comments]
end
