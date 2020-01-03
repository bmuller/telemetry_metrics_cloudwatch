defmodule TelemetryMetricsCloudwatch.MixProject do
  use Mix.Project

  @version "0.2.1"

  def project do
    [
      app: :telemetry_metrics_cloudwatch,
      aliases: aliases(),
      version: @version,
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Provides an AWS CloudWatch reporter for Telemetry Metrics definitions.",
      package: package(),
      source_url: "https://github.com/bmuller/telemetry_metrics_cloudwatch",
      docs: [
        source_ref: "v#{@version}",
        main: "TelemetryMetricsCloudwatch",
        formatters: ~w(html epub)
      ]
    ]
  end

  defp aliases do
    [
      test: [
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
      links: %{"GitHub" => "https://github.com/bmuller/telemetry_metrics_cloudwatch"}
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
      {:ex_doc, "~> 0.18", only: :dev},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:telemetry_metrics, "~> 0.3"}
    ]
  end
end
