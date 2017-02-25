require IEx

defmodule CreamTest do
  use ExUnit.Case
  doctest Cream

  import ExUnit.CaptureLog

  setup do
    Logger.configure(level: :info)

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    user = %User{name: "Chris"} |> Repo.insert!
    Ecto.build_assoc(user, :email, address: "cjb@dumb.com") |> Repo.insert!

    post = Ecto.build_assoc(user, :posts, title: "Dumb Article") |> Repo.insert!
    Ecto.build_assoc(post, :comments, body: "Go home") |> Repo.insert!
    Ecto.build_assoc(post, :comments, body: "You're drunk") |> Repo.insert!

    post = Ecto.build_assoc(user, :posts, title: "Stupid Article") |> Repo.insert!
    Ecto.build_assoc(post, :comments, body: "Why") |> Repo.insert!
    Ecto.build_assoc(post, :comments, body: "Boo") |> Repo.insert!

    user = %User{name: "Callie"} |> Repo.insert!
    Ecto.build_assoc(user, :email, address: "crb@smart.com") |> Repo.insert!

    post = Ecto.build_assoc(user, :posts, title: "Smart Article") |> Repo.insert!
    Ecto.build_assoc(post, :comments, body: "Yes") |> Repo.insert!
    Ecto.build_assoc(post, :comments, body: "Love it") |> Repo.insert!

    post = Ecto.build_assoc(user, :posts, title: "Brilliant Article") |> Repo.insert!
    Ecto.build_assoc(post, :comments, body: "Great") |> Repo.insert!
    Ecto.build_assoc(post, :comments, body: "So good") |> Repo.insert!

    Cream.flush

    :ok
  end

  test "multi fetch" do
    import Ecto.Query

    posts = Repo.all(Post)
    keys = Enum.map(posts, &("post:title:#{&1.id}") )

    titles_by_cache = Cream.fetch(keys, fn missing_keys ->

      post_ids = missing_keys |> Enum.map(fn key ->
        String.split(key, ":") |> List.last |> String.to_integer
      end)

      posts = from(p in Post, where: p.id in ^post_ids) |> Repo.all

      Enum.reduce(posts, %{}, fn post, acc ->
        Map.put acc, "post:title:#{post.id}", post.title
      end)

    end)

    titles_by_db = Enum.reduce posts, %{}, fn(post, acc) ->
      Map.put(acc, "post:title:#{post.id}", post.title)
    end

    assert titles_by_cache == titles_by_db
  end

  test "multi fetch doesn't execute callback every time" do
    Logger.configure(level: :debug)

    log = capture_log fn ->
      Cream.fetch(~w(1 2), fn(missing_keys) ->
        Enum.reduce missing_keys, %{}, fn key, acc -> Map.put(acc, key, key) end
      end)
    end
    assert log =~ "hits:0"
    assert log =~ "misses:2"

    log = capture_log fn ->
      Cream.fetch(~w(1 2), fn(missing_keys) ->
        Enum.reduce missing_keys, %{}, fn key, acc -> Map.put(acc, key, key) end
      end)
    end
    assert log =~ "hits:2"
    assert log =~ "misses:0"

    log = capture_log fn ->
      Cream.fetch(~w(1 2 3), fn(missing_keys) ->
        Enum.reduce missing_keys, %{}, fn key, acc -> Map.put(acc, key, key) end
      end)
    end
    assert log =~ "hits:2"
    assert log =~ "misses:1"
  end

  test "preload belongs_to" do
    comments = Repo.all(Comment)
    comments_from_db = Repo.preload(comments, [:post])

    Logger.configure(level: :debug)

    log = capture_log fn ->
      comments_from_cache = Cream.preload(comments, :post)
      assert comments_from_db == comments_from_cache
    end
    assert log =~ "efficiency:0%"

    log = capture_log fn ->
      comments_from_cache = Cream.preload(comments, :post)
      assert comments_from_db == comments_from_cache
    end
    assert log =~ "efficiency:100%"
    refute log =~ "efficiency:0%"
  end

  test "preload has_many" do
    posts = Repo.all(Post)
    posts_from_db = Repo.preload(posts, [:comments]) |> sort

    Logger.configure(level: :debug)

    log = capture_log fn ->
      posts_from_cache =  Cream.preload(posts, :comments) |> sort
      assert posts_from_db == posts_from_cache
    end
    assert log =~ "efficiency:0%"

    log = capture_log fn ->
      posts_from_cache = Cream.preload(posts, :comments) |> sort
      assert posts_from_db == posts_from_cache
    end
    assert log =~ "efficiency:100%"
    refute log =~ "efficiency:0%"
  end

  test "preload has_one" do
    users = Repo.all(User)
    users_from_db = Repo.preload(users, [:email])

    Logger.configure(level: :debug)

    log = capture_log fn ->
      users_from_cache = Cream.preload(users, :email)
      assert users_from_db == users_from_cache
    end
    assert log =~ "efficiency:0%"

    log = capture_log fn ->
      users_from_cache = Cream.preload(users, :email)
      assert users_from_db == users_from_cache
    end
    assert log =~ "efficiency:100%"
    refute log =~ "efficiency:0%"
  end

  test "preload array" do
    users = Repo.all(User)

    users_from_d = Repo.preload(users, [:email, :posts])
    users_from_c = Cream.preload(users, [:email, :posts])

    assert sort(users_from_d) == sort(users_from_c)
  end

  test "preload hash" do
    users = Repo.all(User)

    users_from_d = Repo.preload(users, [posts: [comments: :post]])
    users_from_c = Cream.preload(users, [posts: [comments: :post]])

    assert sort(users_from_d) == sort(users_from_c)
  end

  defp sort(records) when is_list(records) do
    Enum.map(records, &sort(&1)) |> Enum.sort
  end

  defp sort(%{__struct__: _} = record) do
    if :__schema__ in Keyword.keys(record.__struct__.module_info(:functions)) do
      fields = record.__struct__.__schema__(:associations)
      Enum.reduce fields, record, fn k, acc ->
        v = Map.get(acc, k) |> sort
        Map.put(acc, k, v)
      end
    else
      record
    end
  end

  defp sort(record), do: record

end
