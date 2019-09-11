defmodule TelemetryMetricsCloudwatch.Cloudwatch do
  @moduledoc """
  Functions for interacting with [Amazon CloudWatch](https://aws.amazon.com/cloudwatch/).
  """

  require Logger

  def send_metrics(metric_data, namespace) do
    # gzip, since we've got a max 40 KB payload
    metric_data
    |> ExAws.Cloudwatch.put_metric_data(namespace)
    |> Map.put(:content_encoding, "gzip")
    |> ExAws.request()
    |> log_result(length(metric_data), namespace)
  end

  defp log_result({:ok, _resp}, count, namespace),
    do:
      Logger.debug(
        "#{__MODULE__} pushed #{count} metrics to cloudwatch in namespace #{namespace}"
      )

  defp log_result({:error, resp}, count, namespace),
    do:
      Logger.error(
        "#{__MODULE__} failed to push #{count} metrics to cloudwatch in namespace #{namespace}: #{
          inspect(resp)
        }"
      )
end
