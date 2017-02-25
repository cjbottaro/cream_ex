defmodule Comment do
  use Ecto.Schema

  schema "comments" do
    field :body, :string, null: false
    belongs_to :post, Post
    timestamps()
  end

end
