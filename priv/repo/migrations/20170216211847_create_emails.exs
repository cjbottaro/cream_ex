defmodule Repo.Migrations.CreateEmails do
  use Ecto.Migration

  def change do
    create table(:emails) do
      add :user_id, references(:users), null: false
      add :address, :string, null: false
      timestamps()
    end
  end
end
