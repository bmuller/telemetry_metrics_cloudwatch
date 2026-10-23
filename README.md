# TelemetryMetricsCloudwatch
[![Build Status](https://github.com/bmuller/telemetry_metrics_cloudwatch/actions/workflows/ci.yml/badge.svg)](https://github.com/bmuller/telemetry_metrics_cloudwatch/actions/workflows/ci.yml)
[![Hex pm](https://img.shields.io/hexpm/v/telemetry_metrics_cloudwatch.svg?style=flat)](https://hex.pm/packages/telemetry_metrics_cloudwatch)
[![API Docs](https://img.shields.io/badge/api-docs-lightgreen.svg?style=flat)](https://hexdocs.pm/telemetry_metrics_cloudwatch/)

This is a [Amazon CloudWatch](https://aws.amazon.com/cloudwatch/) Reporter for [`Telemetry.Metrics`](https://github.com/beam-telemetry/telemetry_metrics) definitions.

## Installation

To install `telemetry_metrics_cloudwatch`, just add an entry to your `mix.exs`:

```elixir
def deps do
  [
    {:telemetry_metrics_cloudwatch, "~> 1.1"},
    {:req, "~> 0.7.2"},
    {:aws_credentials, "~> 1.0"}
  ]
end
```

(Check [Hex](https://hex.pm/packages/telemetry_metrics_cloudwatch) to make sure you're using an up-to-date version number.)

Metrics are sent to CloudWatch by a client, and the client you pick decides which
dependency you need.  See [AWS Setup](#aws-setup) below.

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

  defp metrics do
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

To write [high-resolution metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html#high-resolution-metrics=), supply the `:storage_resolution` option (which can be the default of `:standard` or `:high`):

```elixir
counter(
  "http.request.count",
  reporter_options: [storage_resolution: :high]
)
```

### When Data is Sent

Cloudwatch has [certain constraints](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html)
on the number of metrics that can be sent up at any given time.  `TelemetryMetricsCloudwatch`
will send accumulated metric data at least every minute (configurable by the `:push_interval`
option) or when the data cache has reached the maximum size that CloudWatch will accept.

### Event Sampling
You can optionally send only a portion of reported events to CloudWatch via the `:sample_rate` option.  This parameter should contain a value between 0.0 and 1.0 (inclusive), and represents the proportion of events that will be reported.  For instance, a sample rate value of 0.0 will ensure no events are sent, whereas a sample rate value of 1.0 will ensure all events are sent. A sample rate of 0.25 will result in roughly a quarter of all events being sent.

*Note:* Using a sampling rate of less than 1.0 will result in incorrect values for the "Sum" and "Counter" metric types (and some of the values like min/max for the "Summary" metric type) due to the under-reporting of events.  You should only use a sampling rate of less than 1.0 if you have a guaranteed high rate of events and only care about summary statistics like averages and percentiles.

### Units
  
In order to report metrics in the CloudWatch UI, they must be one of the following values:

  * Time units: `:second`, `:microsecond`, `:millisecond`
  * Byte sizes: `:byte`, `:kilobyte`, `:megabyte`, `:gigabyte`, `:terabyte`
  * Bit sizes: `:bit`, `:kilobit`, `:megabit`, `:gigabit`, `:terabit`

For `Telementry.Metrics.Counter`s, the unit will always be `:count`.  Otherwise, the unit will be treated as `nil`.

### AWS Setup

Metrics are sent to CloudWatch by a `TelemetryMetricsCloudwatch.Cloudwatch` client.  Two ship
with this library, and both of their dependencies are optional, so add the one that goes with
the client you want:

  * `TelemetryMetricsCloudwatch.Cloudwatch.Req` (the default) calls the CloudWatch API directly
    over [`Req`](https://hexdocs.pm/req/Req.html), with no AWS SDK in between.  It needs `:req`,
    and `:aws_credentials` unless you configure static credentials.
  * `TelemetryMetricsCloudwatch.Cloudwatch.ExAws` uses
    [`ExAws`](https://hexdocs.pm/ex_aws/ExAws.html), and needs `:ex_aws_cloudwatch`.

The client is resolved from the `:client` option passed to
`TelemetryMetricsCloudwatch.start_link/1`, then the application environment, and finally from
whichever dependency is available (preferring `Req`):

```elixir
config :telemetry_metrics_cloudwatch, client: TelemetryMetricsCloudwatch.Cloudwatch.ExAws
```

The `Req` client picks up credentials and region from the `:telemetry_metrics_cloudwatch`
`:req` application environment, then `:aws_credentials`, then the usual `AWS_*` environment
variables, so the common case needs no configuration at all:

```elixir
config :telemetry_metrics_cloudwatch, :req,
  region: "us-east-2",
  access_key_id: "AKIA...",
  secret_access_key: "...",
  req_options: [retry: false]
```

Whichever client you use, make sure your keys have the
[correct permissions](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/permissions-reference-cw.html) of `cloudwatch:PutMetricData`.

Up to 10 tags are sent up to AWS as dimensions for a given metric.

## Running Tests

To run tests:

```shell
$ mix test
```

## Reporting Issues

Please report all issues [on github](https://github.com/bmuller/telemetry_metrics_cloudwatch/issues).
