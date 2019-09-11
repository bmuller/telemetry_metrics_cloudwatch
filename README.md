# TelemetryMetricsCloudwatch
[![Build Status](https://secure.travis-ci.org/bmuller/telemetry_metrics_cloudwatch.png?branch=master)](https://travis-ci.org/bmuller/telemetry_metrics_cloudwatch)
[![Hex pm](http://img.shields.io/hexpm/v/telemetry_metrics_cloudwatch.svg?style=flat)](https://hex.pm/packages/telemetry_metrics_cloudwatch)
[![API Docs](https://img.shields.io/badge/api-docs-lightgreen.svg?style=flat)](https://hexdocs.pm/telemetry_metrics_cloudwatch/)

This is a [Amazon CloudWatch](https://aws.amazon.com/cloudwatch/) Reporter for [`Telemetry.Metrics`](https://github.com/beam-telemetry/telemetry_metrics) definitions.

## Installation

To install `telemetry_metrics_cloudwatch`, just add an entry to your `mix.exs`:

```elixir
def deps do
  [
    {:telemetry_metrics_cloudwatch, "~> 0.1"}
  ]
end
```

(Check [Hex](https://hex.pm/packages/telemetry_metrics_cloudwatch) to make sure you're using an up-to-date version number.)

## Usage

Provide a list of metric definitions to the `init/2` function. It's recommended to
run TelemetryMetricsCloudwatch under a supervision tree, usually under Application.

```elixir
  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      {TelemetryMetricsCloudwatch, [metrics: metrics()]}
      ...
    ]

    opts = [strategy: :one_for_one, name: ExampleApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp metrics, do:
    [
      counter("http.request.count"),
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.total_run_queue_lengths.total")
    ]
  end
```

You can also provide options for the namespace used in CloudWatch (by default, "Telemetry")
and the minimum frequency (in milliseconds) with which data will be posted (see section 
below for posting rules).  For instance:

```elixir
  ...
  children = [
    {TelemetryMetricsCloudwatch, metrics: metrics(), namespace: "Backend", push_interval: 30_000}
  ]
  ...
```

### Telemetry.Metrics Types Supported

`TelemetryMetricsCloudwatch` supports 3 of the [Metrics](https://hexdocs.pm/telemetry_metrics/Telemetry.Metrics.html#module-metrics):

  * [Counter](https://hexdocs.pm/telemetry_metrics/Telemetry.Metrics.html#counter/2):
    Counter metric keeps track of the total number of specific events emitted.
  * [LastValue](https://hexdocs.pm/telemetry_metrics/Telemetry.Metrics.html#last_value/2):
    Last value keeps track of the selected measurement found in the most recent event.
  * [Summary](https://hexdocs.pm/telemetry_metrics/Telemetry.Metrics.html#summary/2): Summary
    aggregates measurement's values into statistics, e.g. minimum and maximum, mean, or percentiles.
    This sends every measurement to CloudWatch. 

These metrics are sent to CloudWatch based on the rules described below.

### When Data is Sent

Cloudwatch has [certain constraints](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html)
on the number of metrics that can be sent up at any given time.  `TelemetryMetricsCloudwatch`
will send accumulated metric data at least every minute (configurable by the `:push_interval`
option) or when the data cache has reached the maximum size that CloudFront will accept.

### Units
  
In order to report metrics in the CloudWatch UI, they must be one of the following values:

  * Time units: `:second`, `:microsecond`, `:millisecond`
  * Byte sizes: `:byte`, `:kilobyte`, `:megabyte`, `:gigabyte`, `:terabyte`
  * Bit sizes: `:bit`, `:kilobit`, `:megabit`, `:gigabit`, `:terabit`

For `Telementry.Metrics.Counter`s, the unit will always be `:count`.  Otherwise, the unit will be treated as `nil`.

### ExAws Setup

[`ExAws`](https://hexdocs.pm/ex_aws/ExAws.html) is the library used to send metrics to CloudWatch.  Make sure your
[keys are configured](https://hexdocs.pm/ex_aws/ExAws.html#module-aws-key-configuration) and that they have the
[correct permissions](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/permissions-reference-cw.html) of `cloudwatch:PutMetricData`.

Up to 10 tags are sent up to AWS as dimensions for a given metric.

## Running Tests

To run tests:

```shell
$ mix test
```

## Reporting Issues

Please report all issues [on github](https://github.com/bmuller/telemetry_metrics_cloudwatch/issues).
