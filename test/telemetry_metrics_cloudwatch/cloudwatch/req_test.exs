defmodule TelemetryMetricsCloudwatch.Cloudwatch.ReqTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias TelemetryMetricsCloudwatch.Cloudwatch.Req.{MetricData, Request}

  @client TelemetryMetricsCloudwatch.Cloudwatch.Req

  @counter [
    metric_name: "aname.value.count",
    value: 3,
    dimensions: [host: "a host", port: "123"],
    unit: "Count",
    storage_resolution: 60
  ]

  @summary [
    metric_name: "aname.value.summary",
    values: [1, 2.5],
    dimensions: [],
    unit: "Milliseconds",
    storage_resolution: 1
  ]

  @error_response """
  <ErrorResponse xmlns="http://monitoring.amazonaws.com/doc/2010-08-01/">
    <Error>
      <Type>Sender</Type>
      <Code>InvalidParameterValue</Code>
      <Message>The value for parameter MetricName is invalid.</Message>
    </Error>
  </ErrorResponse>
  """

  describe "Encoding metric data" do
    test "should encode a value with its dimensions" do
      assert MetricData.put_metric_data_params([@counter], "Telemetry") == [
               {"Namespace", "Telemetry"},
               {"MetricData.member.1.MetricName", "aname.value.count"},
               {"MetricData.member.1.Value", "3"},
               {"MetricData.member.1.Dimensions.member.1.Name", "host"},
               {"MetricData.member.1.Dimensions.member.1.Value", "a host"},
               {"MetricData.member.1.Dimensions.member.2.Name", "port"},
               {"MetricData.member.1.Dimensions.member.2.Value", "123"},
               {"MetricData.member.1.Unit", "Count"},
               {"MetricData.member.1.StorageResolution", "60"}
             ]
    end

    test "should encode every value of a summary" do
      assert MetricData.put_metric_data_params([@summary], "Telemetry") == [
               {"Namespace", "Telemetry"},
               {"MetricData.member.1.MetricName", "aname.value.summary"},
               {"MetricData.member.1.Values.member.1", "1"},
               {"MetricData.member.1.Values.member.2", "2.5"},
               {"MetricData.member.1.Unit", "Milliseconds"},
               {"MetricData.member.1.StorageResolution", "1"}
             ]
    end

    test "should number each metric datum" do
      params = MetricData.put_metric_data_params([@counter, @summary], "Telemetry")

      assert {"MetricData.member.1.MetricName", "aname.value.count"} in params
      assert {"MetricData.member.2.MetricName", "aname.value.summary"} in params
    end

    test "should skip keys without a value" do
      params = MetricData.put_metric_data_params([Keyword.put(@counter, :unit, nil)], "Telemetry")

      refute Enum.any?(params, fn {key, _value} -> String.ends_with?(key, ".Unit") end)
    end

    test "should reject unknown keys" do
      assert_raise ArgumentError, ~r/unsupported metric datum key: :nonsense/, fn ->
        MetricData.put_metric_data_params([[nonsense: true]], "Telemetry")
      end
    end
  end

  describe "Sending metrics" do
    setup do
      configure(plug: capture_plug(200, ""))
      :ok
    end

    test "should post signed, gzipped form parameters to the regional endpoint" do
      @client.send_metrics([@counter], "Telemetry")

      assert_received {:request, conn}

      assert conn.method == "POST"
      assert conn.host == "monitoring.us-east-2.amazonaws.com"

      assert conn.body_params["Action"] == "PutMetricData"
      assert conn.body_params["Version"] == "2010-08-01"
      assert conn.body_params["Namespace"] == "Telemetry"
      assert conn.body_params["MetricData.member.1.MetricName"] == "aname.value.count"
      assert conn.body_params["MetricData.member.1.Value"] == "3"
      assert conn.body_params["MetricData.member.1.Dimensions.member.1.Value"] == "a host"

      [authorization] = Plug.Conn.get_req_header(conn, "authorization")

      assert authorization =~
               ~r|^AWS4-HMAC-SHA256 Credential=AKIAFAKE/\d{8}/us-east-2/monitoring/aws4_request|

      # Req.Plug strips content-encoding once it has decompressed the body, so the
      # signature is what tells us the request went up gzipped.
      assert authorization =~ "content-encoding"
    end

    test "should send one request per chunk of 20 metrics" do
      metric_data = for index <- 1..21, do: Keyword.put(@counter, :value, index)

      @client.send_metrics(metric_data, "Telemetry")

      assert_received {:request, first}
      assert_received {:request, second}
      refute_received {:request, _}

      assert first.body_params["MetricData.member.20.Value"] == "20"
      refute Map.has_key?(first.body_params, "MetricData.member.21.Value")
      assert second.body_params["MetricData.member.1.Value"] == "21"
    end

    test "should not send anything when there are no metrics" do
      @client.send_metrics([], "Telemetry")

      refute_received {:request, _}
    end
  end

  describe "When a request fails the client" do
    test "should log the CloudWatch error code and message" do
      configure(plug: capture_plug(400, @error_response))

      log = capture_log(fn -> @client.send_metrics([@counter], "Telemetry") end)

      assert log =~ "failed to push metrics"
      assert log =~ "InvalidParameterValue: The value for parameter MetricName is invalid."
    end

    test "should fail without credentials" do
      assert Request.call("PutMetricData", [], credentials: [], plug: capture_plug(200, "")) ==
               {:error, :aws_credentials_not_found}

      refute_received {:request, _}
    end

    test "should fail without a region" do
      assert Request.call("PutMetricData", [],
               credentials: [access_key_id: "AKIAFAKE", secret_access_key: "s3cret"],
               region: "",
               plug: capture_plug(200, "")
             ) == {:error, :aws_region_not_found}

      refute_received {:request, _}
    end
  end

  describe "Request options" do
    test "should take the region from the credentials when none is configured" do
      Request.call("PutMetricData", [],
        credentials: [
          access_key_id: "AKIAFAKE",
          secret_access_key: "s3cret",
          region: "eu-west-1"
        ],
        plug: capture_plug(200, "")
      )

      assert_received {:request, conn}
      assert conn.host == "monitoring.eu-west-1.amazonaws.com"
    end

    test "should let :req_options through to Req" do
      configure(
        plug: capture_plug(200, ""),
        req_options: [headers: [{"x-custom", "hello"}]]
      )

      @client.send_metrics([@counter], "Telemetry")

      assert_received {:request, conn}
      assert Plug.Conn.get_req_header(conn, "x-custom") == ["hello"]
    end

    test "should use a configured endpoint as-is" do
      configure(plug: capture_plug(200, ""), endpoint: "https://localhost:4566/")

      @client.send_metrics([@counter], "Telemetry")

      assert_received {:request, conn}
      assert conn.host == "localhost"
      assert conn.port == 4566
    end
  end

  defp configure(config) do
    config = Keyword.merge(default_config(), config)
    Application.put_env(:telemetry_metrics_cloudwatch, :req, config)
    on_exit(fn -> Application.delete_env(:telemetry_metrics_cloudwatch, :req) end)
  end

  defp default_config do
    [
      region: "us-east-2",
      access_key_id: "AKIAFAKE",
      secret_access_key: "s3cret"
    ]
  end

  defp capture_plug(status, body) do
    test_pid = self()

    fn conn ->
      send(test_pid, {:request, conn})
      Plug.Conn.send_resp(conn, status, body)
    end
  end
end
