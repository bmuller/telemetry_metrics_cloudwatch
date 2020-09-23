defmodule TelemetryMetricsCloudwatchTest do
  use ExUnit.Case

  alias Telemetry.Metrics
  alias TelemetryMetricsCloudwatch.Cache

  describe "An empty cache" do
    test "should have the right metric count and max values per metric" do
      empty = %Cache{}
      assert Cache.metric_count(empty) == 0
      assert Cache.max_values_per_metric(empty) == 0
    end
  end

  describe "When handling tags a cache" do
    test "should be able to handle tags with empty/nil values" do
      tvalues = %{host: 'a host', port: 123, something: "", somethingelse: nil}

      counter =
        Metrics.counter([:aname, :value],
          tag_values: &Map.merge(&1, tvalues),
          tags: [:host, :port, :something, :somethingelse]
        )

      cache = Cache.push_measurement(%Cache{}, %{value: 112}, %{}, counter)

      assert Cache.metric_count(cache) == 1
      assert Cache.max_values_per_metric(cache) == 1

      {_postcache, metrics} = Cache.pop_metrics(cache)

      assert metrics == [
               [
                 metric_name: "aname.value.count",
                 value: 1,
                 dimensions: [host: "a host", port: "123"],
                 unit: "Count"
               ]
             ]
    end

    test "should be able to handle tags with non string values" do
      tvalues = %{host: 'a host', port: 123}

      counter =
        Metrics.counter([:aname, :value],
          tag_values: &Map.merge(&1, tvalues),
          tags: [:host, :port]
        )

      cache = Cache.push_measurement(%Cache{}, %{value: 112}, %{}, counter)

      assert Cache.metric_count(cache) == 1
      assert Cache.max_values_per_metric(cache) == 1

      {_postcache, metrics} = Cache.pop_metrics(cache)

      assert metrics == [
               [
                 metric_name: "aname.value.count",
                 value: 1,
                 dimensions: [host: "a host", port: "123"],
                 unit: "Count"
               ]
             ]
    end

    test "should be able to handle more than 10 tags" do
      keys = ~w(a b c d e f g h i j k l m n o p)a
      tvalues = Enum.into(keys, %{}, &{&1, "value"})

      counter =
        Metrics.counter([:aname, :value],
          tag_values: &Map.merge(&1, tvalues),
          tags: keys
        )

      cache = Cache.push_measurement(%Cache{}, %{value: 112}, %{}, counter)

      assert Cache.metric_count(cache) == 1
      assert Cache.max_values_per_metric(cache) == 1

      {_postcache, metrics} = Cache.pop_metrics(cache)

      assert metrics == [
               [
                 metric_name: "aname.value.count",
                 value: 1,
                 dimensions: Enum.take(tvalues, 10),
                 unit: "Count"
               ]
             ]
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

      assert metrics == [
               [metric_name: "aname.value.count", value: 1, dimensions: [], unit: "Count"]
             ]

      assert Cache.metric_count(postcache) == 0
      assert Cache.max_values_per_metric(postcache) == 0
    end

    test "should be able to coalesce multiple count metrics" do
      cache =
        %Cache{}
        |> Cache.push_measurement(%{value: 133}, %{}, Metrics.counter([:aname, :value]))
        |> Cache.push_measurement(%{value: 100}, %{}, Metrics.counter([:aname, :value]))

      assert Cache.metric_count(cache) == 1
      assert Cache.max_values_per_metric(cache) == 1

      # now pop all metrics
      {postcache, metrics} = Cache.pop_metrics(cache)

      assert metrics == [
               [metric_name: "aname.value.count", value: 2, dimensions: [], unit: "Count"]
             ]

      assert Cache.metric_count(postcache) == 0
      assert Cache.max_values_per_metric(postcache) == 0
    end

    test "should be able to coalesce multiple sum metrics" do
      sum_metric = Metrics.sum([:aname, :value])

      cache =
        %Cache{}
        |> Cache.push_measurement(%{value: 133}, %{}, sum_metric)
        |> Cache.push_measurement(%{value: 100}, %{}, sum_metric)

      assert Cache.metric_count(cache) == 1
      assert Cache.max_values_per_metric(cache) == 1

      # now pop all metrics
      {postcache, metrics} = Cache.pop_metrics(cache)

      assert metrics == [
               [metric_name: "aname.value.sum", value: 233, dimensions: [], unit: "None"]
             ]

      assert Cache.metric_count(postcache) == 0
      assert Cache.max_values_per_metric(postcache) == 0
    end

    test "should be able to handle a nil value" do
      cache =
        Cache.push_measurement(%Cache{}, %{value: nil}, %{}, Metrics.counter([:aname, :value]))

      assert Cache.metric_count(cache) == 0

      cache =
        %Cache{}
        |> Cache.push_measurement(%{value: 133}, %{}, Metrics.counter([:aname, :value]))
        |> Cache.push_measurement(%{value: nil}, %{}, Metrics.counter([:aname, :value]))
        |> Cache.push_measurement(%{value: 100}, %{}, Metrics.counter([:aname, :value]))

      assert Cache.metric_count(cache) == 1
      assert Cache.max_values_per_metric(cache) == 1

      # now pop all metrics
      {postcache, metrics} = Cache.pop_metrics(cache)

      assert metrics == [
               [metric_name: "aname.value.count", value: 2, dimensions: [], unit: "Count"]
             ]

      assert Cache.metric_count(postcache) == 0
      assert Cache.max_values_per_metric(postcache) == 0
    end

    test "should be able to handle a non-numeric, non-nil value" do
      cache =
        Cache.push_measurement(%Cache{}, %{value: "hi"}, %{}, Metrics.counter([:aname, :value]))

      assert Cache.metric_count(cache) == 0

      cache =
        %Cache{}
        |> Cache.push_measurement(%{value: 133}, %{}, Metrics.counter([:aname, :value]))
        |> Cache.push_measurement(%{value: "hi"}, %{}, Metrics.counter([:aname, :value]))
        |> Cache.push_measurement(%{value: 100}, %{}, Metrics.counter([:aname, :value]))

      assert Cache.metric_count(cache) == 1
      assert Cache.max_values_per_metric(cache) == 1

      # now pop all metrics
      {postcache, metrics} = Cache.pop_metrics(cache)

      assert metrics == [
               [metric_name: "aname.value.count", value: 2, dimensions: [], unit: "Count"]
             ]

      assert Cache.metric_count(postcache) == 0
      assert Cache.max_values_per_metric(postcache) == 0
    end
  end
end
