# Changelog for v0.3.x

## v0.3.4 (2023-06-30)

### Enhancements

  * Updates to remove warnings for Elixir 1.15

## v0.3.3 (2022-09-22)

### Enhancements

  * Support for storage resolution argument to handle high resolution (#6)
  * Support for the `:sample_rate` option (#7)

## v0.3.2 (2022-05-11)

### Enhancements

 * Made call to attached telemetry event function more performant (#5)

## v0.3.1 (2020-10-15)

### Bug Fixes

 * Fixed `System.stacktrace()` deprecation warning

## v0.3.0 (2020-10-4)

### Enhancements

 * Support was added for the new `:keep` and `:drop` options in [Telemetry.Metrics 0.5.0](https://github.com/beam-telemetry/telemetry_metrics/blob/master/CHANGELOG.md#050)

# Changelog for v0.2.x

## v0.2.4 (2020-10-04)

### Enhancements

 * Support the `Sum` metric type

## v0.2.3 (2020-09-22)

### Bug Fixes

 * Fixed issue where the `:push_interval` option was ignored when less than 60k milliseconds

## v0.2.2 (2020-05-08)

### Deprecations

 * When metric values are nil, a `Logger` debug message is now used instead of a warning message.
   This is due to an increase in libraries sometimes sending `nil`s as values (Ecto, for instance)

## v0.2.1 (2020-01-03)

### Bug Fixes

 * Fixed typos in debug message
 * Fixed typos in docs
 * Fixed syntax of example in README

## v0.2.0 (2019-09-17)

### Enhancements

  * Support multiple metric types for the same metric name
