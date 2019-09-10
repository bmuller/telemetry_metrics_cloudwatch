defmodule TelemetryMetricsCloudwatchTest do
  use ExUnit.Case

  alias TelemetryMetricsCloudwatch.{Cache}
  alias Telemetry.{Metrics}

  describe "An empty cache" do
    test "should have the right metric count and max values per metric" do
      empty = %Cache{}
      assert Cache.metric_count(empty) == 0
      assert Cache.max_values_per_metric(empty) == 0
    end
  end

  describe "When handling counts, a cache" do
    test "should be able to coalesce a single count metric" do
      cache =
        Cache.push_measurement(%Cache{}, %{value: 112}, %{}, Metrics.counter([:aname, :value]))

      assert Cache.metric_count(cache) == 1
      assert Cache.max_values_per_metric(cache) == 1

      # now pop all metrics
      {postcache, metrics} = Cache.pop_metrics(cache)
      assert metrics == [[metric_name: "aname.value", value: 1, dimensions: [], unit: "Count"]]
      assert Cache.metric_count(postcache) == 0
      assert Cache.max_values_per_metric(postcache) == 0
    end

    test "should be able to coalesce multiple count metrics" do
      cache =
        Cache.push_measurement(%Cache{}, %{value: 133}, %{}, Metrics.counter([:aname, :value]))

      cache = Cache.push_measurement(cache, %{value: 100}, %{}, Metrics.counter([:aname, :value]))
      assert Cache.metric_count(cache) == 1
      assert Cache.max_values_per_metric(cache) == 1

      # now pop all metrics
      {postcache, metrics} = Cache.pop_metrics(cache)
      assert metrics == [[metric_name: "aname.value", value: 2, dimensions: [], unit: "Count"]]
      assert Cache.metric_count(postcache) == 0
      assert Cache.max_values_per_metric(postcache) == 0
    end
  end
end
