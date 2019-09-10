# https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html
# https://hexdocs.pm/elixir/GenServer.html#module-receiving-regular-messages

defmodule TelemetryMetricsCloudwatch do
  @moduledoc """
  Documentation for TelemetryMetricsCloudwatch.
  """

  use GenServer
  require Logger
  alias TelemetryMetricsCloudwatch.Cache

  def start_link(opts) do
    server_opts = Keyword.take(opts, [:name])

    metrics =
      opts[:metrics] ||
        raise ArgumentError, "the :metrics option is required by #{inspect(__MODULE__)}"

    Cache.validate_metrics(metrics)

    namespace = Keyword.get(opts, :namespace, "Telemetry")
    GenServer.start_link(__MODULE__, {metrics, namespace}, server_opts)
  end

  @impl true
  def init({metrics, namespace}) do
    Process.flag(:trap_exit, true)
    groups = Enum.group_by(metrics, & &1.event_name)

    for {event, metrics} <- groups do
      id = {__MODULE__, event, self()}
      :telemetry.attach(id, event, &handle_telemetry_event/4, {self(), metrics})
    end

    schedule_push_check()

    {:ok,
     %Cache{
       metric_names: Map.keys(groups),
       namespace: namespace,
       last_run: System.monotonic_time(:second)
     }}
  end

  defp handle_telemetry_event(_event_name, measurements, metadata, {pid, metrics}),
    do: Kernel.send(pid, {:handle_event, measurements, metadata, metrics})

  @impl true
  def handle_info(:push_check, state) do
    schedule_push_check()
    {:noreply, push_check(state)}
  end

  @impl true
  def handle_info({:handle_event, measurements, metadata, metrics}, state) do
    newstate =
      Enum.reduce(metrics, state, fn metric, state ->
        state
        |> Cache.push_measurement(measurements, metadata, metric)
        |> push_check()
      end)

    {:noreply, newstate}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  defp schedule_push_check, do: Process.send_after(self(), :push_check, 60_000)

  defp push_check(%Cache{last_run: last_run} = state) do
    # https://docs.aws.amazon.com/cli/latest/reference/cloudwatch/put-metric-data.html
    # We can publish up to 150 values per metric for up to 20 different metrics
    metric_count = Cache.metric_count(state)
    metric_age = System.monotonic_time(:second) - last_run

    cond do
      metric_age >= 60 and metric_count > 0 ->
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
    metric_count = Cache.metric_count(state)
    {state, metric_data} = Cache.pop_metrics(state)

    # gzip, since we've got a max 40 KB payload
    request =
      metric_data
      |> ExAws.Cloudwatch.put_metric_data(namespace)
      |> Map.put(:content_encoding, "gzip")

    request
    |> ExAws.request()
    |> case do
      {:ok, _resp} ->
        Logger.debug(
          "#{__MODULE__} pushed #{metric_count} metrics to cloudwatch in namespace #{namespace}"
        )

      {:error, resp} ->
        Logger.error(
          "#{__MODULE__} could not push #{metric_count} metrics to cloudwatch: #{inspect(resp)}"
        )
    end

    Map.put(state, :last_run, System.monotonic_time(:second))
  end

  @impl true
  def terminate(_, %Cache{metric_names: events}) do
    for event <- events do
      :telemetry.detach({__MODULE__, event, self()})
    end

    :ok
  end
end
