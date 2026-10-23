defmodule TelemetryMetricsCloudwatch.Cloudwatch.Req.Request do
  @moduledoc false

  # The CloudWatch API speaks the AWS Query protocol: form encoded parameters in,
  # XML out.
  @api_version "2010-08-01"
  @service :monitoring

  @default_req_options [retry: :transient, max_retries: 2]

  @type options :: [
          credentials: map() | keyword(),
          endpoint: String.t(),
          plug: term(),
          region: String.t(),
          req_options: keyword()
        ]

  @doc """
  Sends one CloudWatch API request.

  The request is form encoded, gzipped (CloudWatch accepts a limited payload
  size) and signed with AWS Signature Version 4.  Credentials can be supplied in
  `opts` or are loaded from `aws_credentials`.
  """
  @spec call(String.t(), [{String.t(), String.t()}], options()) ::
          {:ok, binary()} | {:error, term()}
  def call(action, params, opts \\ []) when is_binary(action) and is_list(params) do
    with {:ok, credentials} <- credentials(opts),
         {:ok, region} <- region(opts, credentials),
         req = request(opts, credentials, region),
         {:ok, response} <-
           Req.post(req, form: [{"Action", action}, {"Version", @api_version} | params]) do
      if response.status in 200..299 do
        {:ok, response.body}
      else
        {:error, {:http_error, response.status, error_reason(response.body)}}
      end
    end
  end

  defp request(opts, credentials, region) do
    [
      url: Keyword.get(opts, :endpoint, "https://monitoring.#{region}.amazonaws.com/"),
      plug: Keyword.get(opts, :plug),
      # gzip, since we've got a max 40 KB payload.  This runs before the request
      # is signed, so the signature covers the compressed body.
      compress_body: true,
      aws_sigv4: [
        access_key_id: credentials[:access_key_id],
        secret_access_key: credentials[:secret_access_key],
        token: credentials[:token],
        region: region,
        service: @service
      ]
    ]
    |> Keyword.merge(@default_req_options)
    |> Keyword.merge(Keyword.get(opts, :req_options, []))
    |> Req.new()
  end

  defp credentials(opts) do
    credentials =
      opts
      |> Keyword.get_lazy(:credentials, &aws_credentials/0)
      |> normalize_credentials()

    if credentials[:access_key_id] && credentials[:secret_access_key] do
      {:ok, credentials}
    else
      {:error, :aws_credentials_not_found}
    end
  end

  defp aws_credentials do
    if Code.ensure_loaded?(:aws_credentials) do
      case :aws_credentials.get_credentials() do
        credentials when is_map(credentials) -> credentials
        _ -> environment_credentials()
      end
    else
      environment_credentials()
    end
  end

  defp environment_credentials do
    %{
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
      token: System.get_env("AWS_SESSION_TOKEN")
    }
  end

  defp normalize_credentials(credentials) when is_list(credentials), do: Map.new(credentials)
  defp normalize_credentials(credentials) when is_map(credentials), do: credentials
  defp normalize_credentials(_credentials), do: %{}

  defp region(opts, credentials) do
    region =
      Keyword.get(opts, :region) || credentials[:region] || System.get_env("AWS_REGION") ||
        System.get_env("AWS_DEFAULT_REGION")

    case region do
      region when is_binary(region) and region != "" -> {:ok, region}
      _ -> {:error, :aws_region_not_found}
    end
  end

  # CloudWatch reports errors as <ErrorResponse><Error>...</Error></ErrorResponse>,
  # so pull out the interesting bits rather than taking on an XML parser.
  defp error_reason(body) when is_binary(body) do
    with [_, code] <- Regex.run(~r{<Code>([^<]*)</Code>}, body),
         [_, message] <- Regex.run(~r{<Message>([^<]*)</Message>}, body) do
      "#{code}: #{message}"
    else
      _ -> body
    end
  end

  defp error_reason(body), do: inspect(body)
end
