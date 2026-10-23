defmodule TelemetryMetricsCloudwatch.Cloudwatch.Req do
  @moduledoc """
  `Req` implementation of the `TelemetryMetricsCloudwatch.Cloudwatch` behaviour.

  This client talks to the CloudWatch API directly over
  [`Req`](https://hexdocs.pm/req/Req.html), with no AWS SDK in between.  It
  requires `:req` and, unless you configure static credentials, `:aws_credentials`:

      def deps do
        [
          {:req, "~> 0.7.2"},
          {:aws_credentials, "~> 1.0"}
        ]
      end

  Credentials and region are resolved per request, in this order:

    * the `:telemetry_metrics_cloudwatch` `:req` application environment
    * `:aws_credentials`, when that application is available
    * the `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_SESSION_TOKEN`
      environment variables, and `AWS_REGION` / `AWS_DEFAULT_REGION` for the region

  Everything is optional, so the usual case is no configuration at all.  To pin
  things down:

      config :telemetry_metrics_cloudwatch, :req,
        region: "us-east-2",
        access_key_id: "AKIA...",
        secret_access_key: "...",
        token: "...",
        endpoint: "https://monitoring.us-east-2.amazonaws.com/",
        req_options: [retry: false]

  `:req_options` are merged into `Req.new/1`, so anything `Req` accepts (pools,
  timeouts, retries) can be set there.
  """

  @behaviour TelemetryMetricsCloudwatch.Cloudwatch
  @chunk_size 20

  alias TelemetryMetricsCloudwatch.Cloudwatch.Req.{MetricData, Request}

  require Logger

  @impl true
  def send_metrics(metric_data, namespace) do
    options = request_options()

    metric_data
    |> Enum.chunk_every(@chunk_size)
    |> Enum.each(fn chunk ->
      "PutMetricData"
      |> Request.call(MetricData.put_metric_data_params(chunk, namespace), options)
      |> log_result(chunk, namespace)
    end)
  end

  defp request_options do
    config = Application.get_env(:telemetry_metrics_cloudwatch, :req, [])

    []
    |> put_option(:region, config[:region])
    |> put_option(:credentials, credentials_from_config(config))
    |> put_option(:endpoint, config[:endpoint])
    |> put_option(:plug, config[:plug])
    |> put_option(:req_options, config[:req_options])
  end

  defp credentials_from_config(config) do
    credentials = Keyword.take(config, [:access_key_id, :secret_access_key, :token])

    if credentials[:access_key_id] && credentials[:secret_access_key], do: credentials
  end

  defp put_option(options, _key, nil), do: options
  defp put_option(options, key, value), do: Keyword.put(options, key, value)

  defp log_result({:ok, _resp}, metric_data, namespace) do
    msg =
      "#{__MODULE__} pushed #{length(metric_data)} metrics to cloudwatch in namespace #{namespace}"

    Logger.debug(msg)
  end

  defp log_result({:error, resp}, metric_data, namespace) do
    msg =
      "#{__MODULE__} failed to push metrics #{inspect(metric_data)} to cloudwatch in namespace #{namespace}: #{inspect(resp)}"

    Logger.error(msg)
  end
end
