defmodule Coder.Test do
  use ExUnit.Case

  alias Cream.Coder

  test "jason" do
    {:ok, json, 0b1} = Coder.apply_encode(Coder.Jason, %{"foo" => "bar"}, 0)
    {:ok, %{"foo" => "bar"}} = Jason.decode(json)

    {:ok, json, 0b101} = Coder.apply_encode(Coder.Jason, %{"foo" => "bar"}, 0b100)
    {:ok, %{"foo" => "bar"}} = Jason.decode(json)

    {:error, _reason} = Coder.apply_encode(Coder.Jason, {"foo", "bar"}, 0b100)

    {:ok, json, flags} = Coder.apply_encode(Coder.Jason, %{"foo" => "bar"}, 0)
    {:ok, %{"foo" => "bar"}} = Coder.apply_decode(Coder.Jason, json, flags)

    {:ok, json, flags} = Coder.apply_encode(Coder.Jason, %{"foo" => "bar"}, 0b100)
    {:ok, %{"foo" => "bar"}} = Coder.apply_decode(Coder.Jason, json, flags)
  end

  test "gzip" do
    {:ok, zipped, 0b10} = Coder.apply_encode(Coder.Gzip, "foobar", 0)
    "foobar" = :zlib.gunzip(zipped)

    {:ok, zipped, 0b110} = Coder.apply_encode(Coder.Gzip, "foobar", 0b100)
    "foobar" = :zlib.gunzip(zipped)

    {:error, _reason} = Coder.apply_encode(Coder.Gzip, :foobar, 0)

    {:ok, zipped, flags} = Coder.apply_encode(Coder.Gzip, "foobar", 0)
    {:ok, "foobar"} = Coder.apply_decode(Coder.Gzip, zipped, flags)

    {:ok, zipped, flags} = Coder.apply_encode(Coder.Gzip, "foobar", 0b100)
    {:ok, "foobar"} = Coder.apply_decode(Coder.Gzip, zipped, flags)
  end

  test "jason + gzip" do
    encoders = [Coder.Jason, Coder.Gzip]
    decoders = [Coder.Gzip, Coder.Jason]

    term = %{"foo" => "bar"}

    {:ok, data, 0b11} = Coder.apply_encode(encoders, term, 0)
    ^term = data |> :zlib.gunzip() |> Jason.decode!()

    {:ok, data, 0b111} = Coder.apply_encode(encoders, term, 0b100)
    ^term = data |> :zlib.gunzip() |> Jason.decode!()

    {:ok, data, 0b11} = Coder.apply_encode(encoders, term, 0)
    {:ok, ^term} = Coder.apply_decode(decoders, data, 0b11)

    {:ok, data, flags} = Coder.apply_encode(encoders, term, 0b100)
    {:ok, ^term} = Coder.apply_decode(decoders, data, flags)
  end

end
