defmodule Cream.Logger do
  @moduledoc false
  require Logger

  def init do
    config = Application.get_env(:cream, __MODULE__, [])
    |> Map.new()

    :telemetry.attach_many(
      inspect(__MODULE__),
      [
        [:cream, :connection, :connect],
        [:cream, :connection, :error],
        [:cream, :connection, :disconnect]
      ],
      &__MODULE__.log/4,
      config
    )
  end

  def log([:cream, :connection, :connect], %{usec: usec}, meta, _config) do
    time = format_usec(usec)
    Logger.debug("Connected to #{meta.server} in #{time}")
  end

  def log([:cream, :connection, :error], %{usec: usec}, meta, _config) do
    time = format_usec(usec)
    Logger.warn("Error connecting to #{meta.server} (#{meta.reason}) in #{time}")
  end

  def log([:cream, :connection, :disconnect], _time, meta, _config) do
    Logger.warn("Disconnected from #{meta.server} (#{meta.reason})")
  end

  def format_usec(usec) do
    if usec < 1000 do
      "#{usec}μs"
    else
      "#{round(usec/1000)}ms"
    end
  end

end
