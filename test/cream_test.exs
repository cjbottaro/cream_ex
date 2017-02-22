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

end
