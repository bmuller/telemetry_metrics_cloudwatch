defmodule TelemetryMetricsCloudwatch do
  @moduledoc """
  This is a [Amazon CloudWatch](https://aws.amazon.com/cloudwatch/) Reporter for
  [`Telemetry.Metrics`](https://github.com/beam-telemetry/telemetry_metrics) definitions.

  Provide a list of metric definitions to the `init/2` function. It's recommended to
  run TelemetryMetricsCloudwatch under a supervision tree, usually under Application.

      def start(_type, _args) do
        # List all child processes to be supervised
        children = [
          {TelemetryMetricsCloudwatch, [metrics: metrics()]}
        ...
        ]

        opts = [strategy: :one_for_one, name: ExampleApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

      defp metrics do
        [
          counter("http.request.count"),
          last_value("vm.memory.total", unit: :byte),
          last_value("vm.total_run_queue_lengths.total")
        ]
      end

  You can also provide options for the namespace used in CloudWatch (by default, "Telemetry")
  and the minimum frequency (in milliseconds) with which data will be posted (see section
  below for posting rules).  For instance:

      ...
      children = [
         {TelemetryMetricsCloudwatch, metrics: metrics(), namespace: "Backend", push_interval: 30_000}
      ]
      ...

  ## Telemetry.Metrics Types Supported

  `TelemetryMetricsCloudwatch` supports 4 of the [Metrics](https://hexdocs.pm/telemetry_metrics/Telemetry.Metrics.html#module-metrics):

    * [Counter](https://hexdocs.pm/telemetry_metrics/Telemetry.Metrics.html#counter/2):
      Counter metric keeps track of the total number of specific events emitted.
    * [LastValue](https://hexdocs.pm/telemetry_metrics/Telemetry.Metrics.html#last_value/2):
      Last value keeps track of the selected measurement found in the most recent event.
    * [Summary](https://hexdocs.pm/telemetry_metrics/Telemetry.Metrics.html#summary/2): Summary
      aggregates measurement's values into statistics, e.g. minimum and maximum, mean, or percentiles.
      This sends every measurement to CloudWatch.
    * [Sum](https://hexdocs.pm/telemetry_metrics/Telemetry.Metrics.html#sum/2): Sum metric keeps track
      of the sum of selected measurement's values carried by specific events.  If you are using Summary
      for a metric already, then CloudWatch can calculate a Sum using that Summary metric.  If you
      only need a Sum (and no other summary metrics) then use this Sum metric instead.

  These metrics are sent to CloudWatch based on the rules described below.

  ## When Data is Sent

  Cloudwatch has [certain constraints](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html)
  on the number of metrics that can be sent up at any given time.  `TelemetryMetricsCloudwatch`
  will send accumulated metric data at least every minute (configurable by the `:push_interval`
  option) or when the data cache has reached the maximum size that CloudWatch will accept.

  ### Event Sampling
  You can control the rate at which your metrics are queued by configuring the `:sample_rate` option using a value
  between 0.0 and 1.0. A sample rate value of 0.0 will ensure no events are sent, whereas a sample rate
  value of 1.0 will ensure all events are sent. If you set the sample rate to 0.25, you would effectively
  queue 25% of your metrics.

  ## Units

  In order to report metrics in the CloudWatch UI, they must be one of the following values:

    * Time units: `:second`, `:microsecond`, `:millisecond`
    * Byte sizes: `:byte`, `:kilobyte`, `:megabyte`, `:gigabyte`, `:terabyte`
    * Bit sizes: `:bit`, `:kilobit`, `:megabit`, `:gigabit`, `:terabit`

  For `Telementry.Metrics.Counter`s, the unit will always be `:count`.  Otherwise, the unit will be treated as `nil`.

  ## Notes on AWS

  [`ExAws`](https://hexdocs.pm/ex_aws/ExAws.html) is the library used to send metrics to CloudWatch.  Make sure your
  [keys are configured](https://hexdocs.pm/ex_aws/ExAws.html#module-aws-key-configuration) and that they have the
  [correct permissions](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/permissions-reference-cw.html) of `cloudwatch:PutMetricData`.

  Up to 10 tags are sent up to AWS as dimensions for a given metric.  Every metric name will have a suffix added based on
  the metric type (CloudWatch doesn't allow different units / measurements with the same name).  So, for instance,
  if your metrics are:

      summary("my_app.repo.query.total_time", unit: {:nanosecond, :millisecond})
      count("my_app.repo.query.total_time")

  Then the metric names in CloudWatch will be:

    * `my_app.repo.query.total_time.summary` (with all data points recorded)
    * `my_app.repo.query.total_time.count` (with the number of queries recorded)

  """

  use GenServer
  require Logger
  alias TelemetryMetricsCloudwatch.{Cache, Cloudwatch}

  @doc """
  Start the `TelemetryMetricsCloudwatch` `GenServer`.

  Available options:
  * `:name` - name of the reporter instance.
  * `:metrics` - a list of `Telemetry.Metrics` to track.
  * `:namespace` - Namespace to use in CloudWatch
  * `:push_interval` - The minimum interval that metrics are guaranteed to be pushed to cloudwatch (in milliseconds)
  * `:sample_rate` - Sampling factor to apply to metrics. 0.0 will deny all events, 1.0 will queue all events.
  """
  def start_link(opts) do
    server_opts = Keyword.take(opts, [:name])

    metrics =
      opts[:metrics] ||
        raise ArgumentError, "the :metrics option is required by #{inspect(__MODULE__)}"

    Cache.validate_metrics(metrics)
    namespace = Keyword.get(opts, :namespace, "Telemetry")
    push_interval = Keyword.get(opts, :push_interval, 60_000)
    sample_rate = Keyword.get(opts, :sample_rate, 1.0)

    GenServer.start_link(
      __MODULE__,
      {metrics, namespace, push_interval, sample_rate},
      server_opts
    )
  end

  @impl true
  def init({metrics, namespace, push_interval, sample_rate}) do
    Process.flag(:trap_exit, true)
    groups = Enum.group_by(metrics, & &1.event_name)

    for {event, metrics} <- groups do
      id = {__MODULE__, event, self()}
      :telemetry.attach(id, event, &__MODULE__.handle_telemetry_event/4, {self(), metrics})
    end

    state = %Cache{
      metric_names: Map.keys(groups),
      namespace: namespace,
      last_run: System.monotonic_time(:second),
      push_interval: push_interval,
      sample_rate: sample_rate
    }

    schedule_push_check(state)

    {:ok, state}
  end

  @impl true
  def handle_info(:push_check, state) do
    schedule_push_check(state)
    {:noreply, push_check(state)}
  end

  @impl true
  def handle_info(
        {:handle_event, measurements, metadata, metrics},
        %Cache{sample_rate: sample_rate} = state
      ) do
    newstate =
      Enum.reduce(metrics, state, fn metric, state ->
        # Here's where to sample
        if sample_measurement?(sample_rate) do
          state
          |> Cache.push_measurement(measurements, metadata, metric)
          |> push_check()
        end
      end)

    {:noreply, newstate}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  def handle_telemetry_event(_event_name, measurements, metadata, {pid, metrics}),
    do: Kernel.send(pid, {:handle_event, measurements, metadata, metrics})

  defp schedule_push_check(%Cache{push_interval: push_interval}),
    do: Process.send_after(self(), :push_check, push_interval)

  defp push_check(%Cache{last_run: last_run, push_interval: push_interval} = state) do
    # https://docs.aws.amazon.com/cli/latest/reference/cloudwatch/put-metric-data.html
    # We can publish up to 150 values per metric for up to 20 different metrics
    metric_count = Cache.metric_count(state)
    metric_age = System.monotonic_time(:second) - last_run
    push_interval = push_interval / 1000

    cond do
      metric_age >= push_interval and metric_count > 0 ->
        push(state)

      metric_count == 20 ->
        push(state)

      Cache.max_values_per_metric(state) == 150 ->
        push(state)

      true ->
        state
    end
  end

  defp push(%Cache{namespace: namespace} = state) do
    {state, metric_data} = Cache.pop_metrics(state)
    Cloudwatch.send_metrics(metric_data, namespace)
    Map.put(state, :last_run, System.monotonic_time(:second))
  end

  @impl true
  def terminate(_, %Cache{metric_names: events}) do
    for event <- events do
      :telemetry.detach({__MODULE__, event, self()})
    end

    :ok
  end

  @spec sample_measurement?(number()) :: boolean()
  defp sample_measurement?(1), do: true
  defp sample_measurement?(1.0), do: true
  defp sample_measurement?(0), do: false
  defp sample_measurement?(0.0), do: false

  defp sample_measurement?(sample_rate) do
    :rand.uniform() < sample_rate
  end
end
