defmodule TelemetryMetricsCloudwatch.MixProject do
  use Mix.Project

  @source_url "https://github.com/bmuller/telemetry_metrics_cloudwatch"
  @version "1.0.0"

  def project do
    [
      app: :telemetry_metrics_cloudwatch,
      aliases: aliases(),
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Provides an AWS CloudWatch reporter for Telemetry Metrics definitions.",
      package: package(),
      source_url: @source_url,
      docs: docs(),
      preferred_cli_env: [test: :test, "ci.test": :test]
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      source_url: @source_url,
      main: "TelemetryMetricsCloudwatch",
      formatters: ~w(html)
    ]
  end

  defp aliases do
    [
      "ci.test": [
        "format --check-formatted",
        "test",
        "credo"
      ]
    ]
  end

  def package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Brian Muller"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      }
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_aws_cloudwatch, "~> 2.0"},
      {:ex_doc, "~> 0.28", only: :dev},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:telemetry_metrics, "~> 1.0"}
    ]
  end
end
