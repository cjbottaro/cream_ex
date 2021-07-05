defmodule Coder.Test do
  use ExUnit.Case

  alias Cream.Coder

  test "jason" do
    {:ok, json, 0b1} = Coder.encode(Coder.Jason, %{"foo" => "bar"}, 0)
    {:ok, %{"foo" => "bar"}} = Jason.decode(json)

    {:ok, json, 0b101} = Coder.encode(Coder.Jason, %{"foo" => "bar"}, 0b100)
    {:ok, %{"foo" => "bar"}} = Jason.decode(json)

    {:error, _reason} = Coder.encode(Coder.Jason, {"foo", "bar"}, 0b100)

    {:ok, json, flags} = Coder.encode(Coder.Jason, %{"foo" => "bar"}, 0)
    {:ok, %{"foo" => "bar"}} = Coder.decode(Coder.Jason, json, flags)

    {:ok, json, flags} = Coder.encode(Coder.Jason, %{"foo" => "bar"}, 0b100)
    {:ok, %{"foo" => "bar"}} = Coder.decode(Coder.Jason, json, flags)
  end

  test "gzip" do
    {:ok, zipped, 0b10} = Coder.encode(Coder.Gzip, "foobar", 0)
    "foobar" = :zlib.gunzip(zipped)

    {:ok, zipped, 0b110} = Coder.encode(Coder.Gzip, "foobar", 0b100)
    "foobar" = :zlib.gunzip(zipped)

    {:error, _reason} = Coder.encode(Coder.Gzip, :foobar, 0)

    {:ok, zipped, flags} = Coder.encode(Coder.Gzip, "foobar", 0)
    {:ok, "foobar"} = Coder.decode(Coder.Gzip, zipped, flags)

    {:ok, zipped, flags} = Coder.encode(Coder.Gzip, "foobar", 0b100)
    {:ok, "foobar"} = Coder.decode(Coder.Gzip, zipped, flags)
  end

  test "jason + gzip" do
    encoders = [Coder.Jason, Coder.Gzip]
    decoders = [Coder.Gzip, Coder.Jason]

    term = %{"foo" => "bar"}

    {:ok, data, 0b11} = Coder.encode(encoders, term, 0)
    ^term = data |> :zlib.gunzip() |> Jason.decode!()

    {:ok, data, 0b111} = Coder.encode(encoders, term, 0b100)
    ^term = data |> :zlib.gunzip() |> Jason.decode!()

    {:ok, data, 0b11} = Coder.encode(encoders, term, 0)
    {:ok, ^term} = Coder.decode(decoders, data, 0b11)

    {:ok, data, flags} = Coder.encode(encoders, term, 0b100)
    {:ok, ^term} = Coder.decode(decoders, data, flags)
  end

end
