defmodule TelemetryMetricsCloudwatch.Cache do
  @moduledoc """
  State for `GenServer`.  Nothing here should be called directly outside of the
  `TelemetryMetricsCloudwatch` module.
  """

  defstruct [
    :metric_names,
    :namespace,
    :last_run,
    :push_interval,
    counters: %{},
    last_values: %{},
    summaries: %{}
  ]

  require Logger

  alias Telemetry.Metrics.{Counter, LastValue, Summary}
  alias __MODULE__

  # the only valid units are: Seconds, Microseconds, Milliseconds, Bytes, Kilobytes,
  # Megabytes, Gigabytes, Terabytes, Bits, Kilobits, Megabits, Gigabits, Terabits
  @valid_units ~w(second microsecond millisecond byte kilobyte megabyte gigabyte
    terabyte bit kilobit megabit gigabit terabit)a

  def push_measurement(cache, measurements, metadata, metric) do
    measurement = extract_measurement(metric, measurements)
    tags = extract_tags(metric, metadata)

    if is_number(measurement) do
      Logger.debug(
        "#{extract_string_name(metric)}[#{metric.__struct__}] recieved with value #{measurement} and tags #{
          inspect(tags)
        }"
      )

      coalesce(cache, metric, measurement, tags)
    else
      Logger.warn(
        "Value for #{inspect(metric)} was non-numeric: #{inspect(measurement)}.  Ignoring."
      )

      cache
    end
  rescue
    e ->
      Logger.error([
        "Could not process metric #{inspect(metric)}",
        Exception.format(:error, e, System.stacktrace())
      ])

      cache
  end

  # if the measurement is nil
  defp coalesce(cache, _metric, nil, _tags), do: cache

  defp coalesce(%Cache{counters: counters} = cache, %Counter{} = metric, _measurement, tags) do
    counters = Map.update(counters, {metric, tags}, 1, &(&1 + 1))
    Map.put(cache, :counters, counters)
  end

  defp coalesce(
         %Cache{last_values: last_values} = cache,
         %LastValue{} = metric,
         measurement,
         tags
       ) do
    lvs = Map.put(last_values, {metric, tags}, measurement)
    Map.put(cache, :last_values, lvs)
  end

  defp coalesce(%Cache{summaries: summaries} = cache, %Summary{} = metric, measurement, tags) do
    summaries = Map.update(summaries, {metric, tags}, [measurement], &(&1 ++ [measurement]))
    Map.put(cache, :summaries, summaries)
  end

  # no idea how to handle this metric
  defp coalesce(cache, _metric, _measurement, _tags), do: cache

  def metric_count(%Cache{counters: counters, last_values: last_values, summaries: summaries}) do
    [counters, last_values, summaries]
    |> Enum.map(&map_size/1)
    |> Enum.reduce(0, &(&1 + &2))
  end

  # If summaries are empty, then the max values for last value or count metrics would
  # just be 1 if there are any keys with values otherwise 0
  def max_values_per_metric(%Cache{summaries: summaries} = cache) when map_size(summaries) == 0,
    do: min(metric_count(cache), 1)

  def max_values_per_metric(%Cache{summaries: summaries}) do
    # Summaries are the only ones that could have more than one
    Enum.reduce(Map.values(summaries), 0, fn measurements, bigsofar ->
      max(bigsofar, length(measurements))
    end)
  end

  defp extract_string_name(%{name: name}),
    do: Enum.map_join(name, ".", &to_string/1)

  defp extract_measurement(metric, measurements) do
    case metric.measurement do
      fun when is_function(fun, 1) -> fun.(measurements)
      key -> measurements[key]
    end
  end

  # extract up to 10 tags, and don't include any empty values
  # because cloudwatch won't handle any empty dimensions
  defp extract_tags(metric, metadata) do
    metadata
    |> metric.tag_values.()
    |> Map.take(metric.tags)
    |> Enum.into([], fn {k, v} -> {k, to_string(v)} end)
    |> Enum.filter(fn {_k, v} -> String.length(v) > 0 end)
    |> Enum.take(10)
  end

  def validate_metrics([]), do: nil

  def validate_metrics([head | rest]) do
    unless Enum.member?([Counter, Summary, LastValue], head.__struct__),
      do: Logger.warn("#{head.__struct__} is not supported by the Reporter #{__MODULE__}")

    validate_metrics(rest)
  end

  def pop_metrics(cache),
    do: Enum.reduce(~w(summaries counters last_values)a, {cache, []}, &pop/2)

  defp pop(:summaries, {cache, items}) do
    nitems =
      cache
      |> Map.get(:summaries)
      |> Enum.map(fn {{metric, tags}, measurements} ->
        [
          metric_name: extract_string_name(metric) <> ".summary",
          values: measurements,
          dimensions: tags,
          unit: get_unit(metric.unit)
        ]
      end)

    {Map.put(cache, :summaries, %{}), items ++ nitems}
  end

  defp pop(:counters, {cache, items}) do
    nitems =
      cache
      |> Map.get(:counters)
      |> Enum.map(fn {{metric, tags}, measurement} ->
        [
          metric_name: extract_string_name(metric) <> ".count",
          value: measurement,
          dimensions: tags,
          unit: "Count"
        ]
      end)

    {Map.put(cache, :counters, %{}), items ++ nitems}
  end

  defp pop(:last_values, {cache, items}) do
    nitems =
      cache
      |> Map.get(:last_values)
      |> Enum.map(fn {{metric, tags}, measurement} ->
        [
          metric_name: extract_string_name(metric) <> ".last_value",
          value: measurement,
          dimensions: tags,
          unit: get_unit(metric.unit)
        ]
      end)

    {Map.put(cache, :last_values, %{}), items ++ nitems}
  end

  defp get_unit(input) do
    if Enum.member?(@valid_units, input) do
      input
      |> to_string()
      |> String.capitalize()
      |> Kernel.<>("s")
    else
      "None"
    end
  end
end
