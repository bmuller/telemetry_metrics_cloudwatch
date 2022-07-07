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
    sums: %{},
    last_values: %{},
    summaries: %{}
  ]

  require Logger

  alias Telemetry.Metrics.{Counter, LastValue, Sum, Summary}
  alias __MODULE__

  # the only valid units are: Seconds, Microseconds, Milliseconds, Bytes, Kilobytes,
  # Megabytes, Gigabytes, Terabytes, Bits, Kilobits, Megabits, Gigabits, Terabits
  @valid_units ~w(second microsecond millisecond byte kilobyte megabyte gigabyte
    terabyte bit kilobit megabit gigabit terabit)a

  @metric_names ~w(summaries counters last_values sums)a

  def push_measurement(cache, measurements, metadata, metric) do
    measurement = extract_measurement(metric, measurements)
    tags = extract_tags(metric, metadata)

    cond do
      is_nil(measurement) ->
        Logger.debug("Ignoring nil value for #{inspect(metric)}")
        cache

      drop?(metric, metadata) ->
        Logger.debug("Dropping value for #{inspect(metric)}")
        cache

      is_number(measurement) ->
        sname = extract_string_name(metric)

        msg =
          "#{sname}[#{metric.__struct__}] received with value #{measurement} and tags #{inspect(tags)}"

        Logger.debug(msg)
        coalesce(cache, metric, measurement, tags)

      true ->
        Logger.warn("Ignoring non-numeric value for #{inspect(metric)}: #{inspect(measurement)}")
        cache
    end
  rescue
    e ->
      Logger.error([
        "Could not process metric #{inspect(metric)}",
        Exception.format(:error, e, __STACKTRACE__)
      ])

      cache
  end

  # if the measurement is nil
  defp coalesce(cache, _metric, nil, _tags), do: cache

  defp coalesce(%Cache{counters: counters} = cache, %Counter{} = metric, _measurement, tags) do
    counters = Map.update(counters, {metric, tags}, 1, &(&1 + 1))
    Map.put(cache, :counters, counters)
  end

  defp coalesce(%Cache{sums: sums} = cache, %Sum{} = metric, measurement, tags) do
    sums = Map.update(sums, {metric, tags}, measurement, &(&1 + measurement))
    Map.put(cache, :sums, sums)
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

  def metric_count(%Cache{} = cache) do
    cache
    |> Map.take(@metric_names)
    |> Map.values()
    |> Enum.map(&map_size/1)
    |> Enum.sum()
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

  defp drop?(%{keep: func}, metadata) when is_function(func, 1),
    do: not func.(metadata)

  defp drop?(%{drop: func}, metadata) when is_function(func, 1),
    do: func.(metadata)

  defp drop?(_metric, _metadata), do: false

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
    unless Enum.member?([Counter, Summary, LastValue, Sum], head.__struct__),
      do: Logger.warn("#{head.__struct__} is not supported by the Reporter #{__MODULE__}")

    validate_metrics(rest)
  end

  def pop_metrics(cache),
    do: Enum.reduce(@metric_names, {cache, []}, &pop/2)

  defp pop(:summaries, {cache, items}) do
    nitems =
      cache
      |> Map.get(:summaries)
      |> Enum.map(fn {{metric, tags}, measurements} ->
        [
          metric_name: extract_string_name(metric) <> ".summary",
          values: measurements,
          dimensions: tags,
          unit: get_unit(metric.unit),
          storage_resolution: get_storage_resolution(metric.reporter_options)
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
          unit: "Count",
          storage_resolution: get_storage_resolution(metric.reporter_options)
        ]
      end)

    {Map.put(cache, :counters, %{}), items ++ nitems}
  end

  defp pop(:sums, {cache, items}) do
    nitems =
      cache
      |> Map.get(:sums)
      |> Enum.map(fn {{metric, tags}, measurement} ->
        [
          metric_name: extract_string_name(metric) <> ".sum",
          value: measurement,
          dimensions: tags,
          unit: get_unit(metric.unit),
          storage_resolution: get_storage_resolution(metric.reporter_options)
        ]
      end)

    {Map.put(cache, :sums, %{}), items ++ nitems}
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
          unit: get_unit(metric.unit),
          storage_resolution: get_storage_resolution(metric.reporter_options)
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

  defp get_storage_resolution(reporter_options) do
    Keyword.get(reporter_options, :storage_resolution, 60)
  end
end
