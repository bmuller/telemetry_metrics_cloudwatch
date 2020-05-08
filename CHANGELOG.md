# Changelog for v0.2.x

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
