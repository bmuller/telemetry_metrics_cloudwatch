defmodule TelemetryMetricsCloudwatch.Cloudwatch do
  @moduledoc """
  Behaviour for interacting with [Amazon CloudWatch](https://aws.amazon.com/cloudwatch/).

  Two clients ship with this library:

    * `TelemetryMetricsCloudwatch.Cloudwatch.Req` - talks to CloudWatch directly
      over `Req`, and requires `:req`
    * `TelemetryMetricsCloudwatch.Cloudwatch.ExAws` - uses
      [`ExAws`](https://hexdocs.pm/ex_aws/ExAws.html), and requires
      `:ex_aws_cloudwatch`

  Both dependencies are optional, so add whichever one goes with the client you
  want.  The client is resolved in this order:

    * the `:client` option passed to `TelemetryMetricsCloudwatch.start_link/1`
    * the `:client` application environment:

          config :telemetry_metrics_cloudwatch, client: TelemetryMetricsCloudwatch.Cloudwatch.Req

    * whichever client's dependency is available, preferring `Req`
  """

  @callback send_metrics(metric_data :: list(), namespace :: String.t()) :: any()

  @clients [
    {__MODULE__.Req, Req},
    {__MODULE__.ExAws, ExAws.Cloudwatch}
  ]

  @doc """
  Returns the client configured in the application environment, or the one whose
  dependency is available.

  Raises if no client can be used.
  """
  @spec default_client() :: module()
  def default_client do
    case Application.get_env(:telemetry_metrics_cloudwatch, :client) do
      nil -> detect_client()
      client -> client
    end
  end

  @doc """
  Checks that `client` can actually be used, and returns it.
  """
  @spec validate_client!(module()) :: module()
  def validate_client!(client) do
    unless Code.ensure_loaded?(client) and function_exported?(client, :send_metrics, 2) do
      raise ArgumentError,
            "#{inspect(client)} is not available as a #{inspect(__MODULE__)} client - " <>
              "it must be a loaded module exporting send_metrics/2"
    end

    client
  end

  defp detect_client do
    Enum.find_value(@clients, &available_client/1) ||
      raise """
      no CloudWatch client is available.  Add one of the following to your deps:

          {:req, "~> 0.7.2"}
          {:ex_aws_cloudwatch, "~> 2.0"}

      or pass a :client of your own to TelemetryMetricsCloudwatch.start_link/1.
      """
  end

  defp available_client({client, dependency}) do
    if Code.ensure_loaded?(dependency), do: client
  end
end
