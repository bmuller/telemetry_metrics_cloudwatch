defmodule TelemetryMetricsCloudwatch.StubClient do
  @moduledoc false

  @behaviour TelemetryMetricsCloudwatch.Cloudwatch

  @impl true
  def send_metrics(metric_data, namespace) do
    send(:telemetry_metrics_cloudwatch_test, {:send_metrics, metric_data, namespace})
  end
end

defmodule TelemetryMetricsCloudwatch.CloudwatchTest do
  use ExUnit.Case, async: false

  alias Telemetry.Metrics
  alias TelemetryMetricsCloudwatch.{Cloudwatch, StubClient}

  describe "Resolving a client" do
    test "should default to the Req client when one isn't configured" do
      assert Cloudwatch.default_client() == Cloudwatch.Req
    end

    test "should use the client from the application environment" do
      Application.put_env(:telemetry_metrics_cloudwatch, :client, Cloudwatch.ExAws)
      on_exit(fn -> Application.delete_env(:telemetry_metrics_cloudwatch, :client) end)

      assert Cloudwatch.default_client() == Cloudwatch.ExAws
    end

    test "should accept a client implementing the behaviour" do
      assert Cloudwatch.validate_client!(StubClient) == StubClient
      assert Cloudwatch.validate_client!(Cloudwatch.Req) == Cloudwatch.Req
      assert Cloudwatch.validate_client!(Cloudwatch.ExAws) == Cloudwatch.ExAws
    end

    test "should reject a module that isn't a client" do
      assert_raise ArgumentError, ~r/is not available as/, fn ->
        Cloudwatch.validate_client!(NoSuchClient)
      end

      assert_raise ArgumentError, ~r/is not available as/, fn ->
        Cloudwatch.validate_client!(TelemetryMetricsCloudwatch.Cache)
      end
    end
  end

  describe "A reporter" do
    setup do
      Process.register(self(), :telemetry_metrics_cloudwatch_test)
      :ok
    end

    test "should send cached metrics through the configured client when it stops" do
      {:ok, pid} =
        TelemetryMetricsCloudwatch.start_link(
          metrics: [Metrics.counter("test.event.count")],
          namespace: "Stubbed",
          client: StubClient
        )

      :telemetry.execute([:test, :event], %{count: 1})
      GenServer.stop(pid)

      assert_received {:send_metrics, metric_data, "Stubbed"}

      assert [[metric_name: "test.event.count.count", value: 1, dimensions: [], unit: "Count"]] =
               Enum.map(metric_data, &Keyword.delete(&1, :storage_resolution))
    end

    test "should not send anything through the client on a dry run" do
      {:ok, pid} =
        TelemetryMetricsCloudwatch.start_link(
          metrics: [Metrics.counter("test.dry.count")],
          client: StubClient,
          dry_run: true
        )

      :telemetry.execute([:test, :dry], %{count: 1})
      GenServer.stop(pid)

      refute_received {:send_metrics, _metric_data, _namespace}
    end

    test "should refuse to start with an invalid client" do
      assert_raise ArgumentError, ~r/is not available as/, fn ->
        TelemetryMetricsCloudwatch.start_link(
          metrics: [Metrics.counter("test.bogus.count")],
          client: NoSuchClient
        )
      end
    end
  end
end
