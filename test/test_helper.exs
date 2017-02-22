ExUnit.start()
Repo.start_link
Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)

defmodule User do
  use Ecto.Schema

  schema "users" do
    field :name, :string, null: false
    has_one :email, Email
    has_many :posts, Post
    timestamps()
  end
end

defmodule Post do
  use Ecto.Schema

  schema "posts" do
    field :title, :string, null: false
    belongs_to :user, User
    has_many :comments, Comment
    timestamps()
  end
end

defmodule Comment do
  use Ecto.Schema

  schema "comments" do
    field :body, :string, null: false
    belongs_to :post, Post
    timestamps()
  end
end

defmodule Email do
  use Ecto.Schema

  schema "emails" do
    field :address, :string, null: false
    belongs_to :user, User
    timestamps()
  end
end
