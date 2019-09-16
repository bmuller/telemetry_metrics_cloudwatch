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
    |> log_result(metric_data, namespace)
  end

  defp log_result({:ok, _resp}, metric_data, namespace),
    do:
      Logger.debug(
        "#{__MODULE__} pushed #{length(metric_data)} metrics to cloudwatch in namespace #{
          namespace
        }"
      )

  defp log_result({:error, resp}, metric_data, namespace),
    do:
      Logger.error(
        "#{__MODULE__} failed to push metrics #{inspect(metric_data)} to cloudwatch in namespace #{
          namespace
        }: #{inspect(resp)}"
      )
end
