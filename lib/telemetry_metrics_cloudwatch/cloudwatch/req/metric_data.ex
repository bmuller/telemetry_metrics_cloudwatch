defmodule TelemetryMetricsCloudwatch.Cloudwatch.Req.MetricData do
  @moduledoc false

  @doc """
  Encodes metric data into `PutMetricData` parameters for the AWS Query protocol.
  """
  @spec put_metric_data_params(list(), String.t()) :: [{String.t(), String.t()}]
  def put_metric_data_params(metric_data, namespace) do
    params =
      metric_data
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {datum, index} -> datum_params(datum, "MetricData.member.#{index}") end)

    [{"Namespace", namespace} | params]
  end

  defp datum_params(datum, prefix), do: Enum.flat_map(datum, &datum_param(&1, prefix))

  defp datum_param({_key, nil}, _prefix), do: []

  defp datum_param({:metric_name, metric_name}, prefix),
    do: [{"#{prefix}.MetricName", to_string(metric_name)}]

  defp datum_param({:value, value}, prefix), do: [{"#{prefix}.Value", to_string(value)}]

  defp datum_param({:values, values}, prefix) do
    values
    |> Enum.with_index(1)
    |> Enum.map(fn {value, index} ->
      {"#{prefix}.Values.member.#{index}", to_string(value)}
    end)
  end

  defp datum_param({:unit, unit}, prefix), do: [{"#{prefix}.Unit", to_string(unit)}]

  defp datum_param({:storage_resolution, resolution}, prefix),
    do: [{"#{prefix}.StorageResolution", to_string(resolution)}]

  defp datum_param({:timestamp, timestamp}, prefix),
    do: [{"#{prefix}.Timestamp", DateTime.to_iso8601(timestamp)}]

  defp datum_param({:dimensions, dimensions}, prefix) do
    dimensions
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{name, value}, index} ->
      [
        {"#{prefix}.Dimensions.member.#{index}.Name", to_string(name)},
        {"#{prefix}.Dimensions.member.#{index}.Value", to_string(value)}
      ]
    end)
  end

  defp datum_param({key, _value}, _prefix) do
    raise ArgumentError, "unsupported metric datum key: #{inspect(key)}"
  end
end
