# lib/all_hands_sing_along/auth/google.ex
defmodule AllHandsSingAlong.Auth.Google do
  @moduledoc """
  Sign in with Google, done by hand with Req: authorization-code flow, then
  the OpenID userinfo endpoint. No JWT verification is needed because the
  tokens come straight from Google over TLS in exchange for the code.

  Enabled when `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` are set. Optional
  `GOOGLE_ALLOWED_DOMAINS` (comma-separated) restricts sign-in to Workspace
  accounts on those domains — the natural setting for an all-hands.
  """

  require Logger

  @authorize_url "https://accounts.google.com/o/oauth2/v2/auth"
  @token_url "https://oauth2.googleapis.com/token"
  @userinfo_url "https://openidconnect.googleapis.com/v1/userinfo"
  @scope "openid email profile"

  @type claims :: %{required(String.t()) => term()}

  @spec enabled?() :: boolean()
  def enabled? do
    Keyword.get(config(), :enabled, false) == true and present?(client_id()) and
      present?(client_secret())
  end

  @spec allowed_domains() :: [String.t()]
  def allowed_domains do
    config()
    |> Keyword.get(:allowed_domains, [])
    |> List.wrap()
    |> Enum.flat_map(&String.split(to_string(&1), ","))
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
  end

  @doc "Random, URL-safe CSRF state to keep in the session across the redirect."
  @spec new_state() :: String.t()
  def new_state, do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)

  @spec authorize_url(String.t(), String.t()) :: String.t()
  def authorize_url(redirect_uri, state) when is_binary(redirect_uri) and is_binary(state) do
    params = %{
      "client_id" => client_id(),
      "redirect_uri" => redirect_uri,
      "response_type" => "code",
      "scope" => @scope,
      "state" => state,
      "access_type" => "online",
      "prompt" => "select_account"
    }

    # `hd` only pre-selects the account picker; the real check is in verify_domain/1.
    params =
      case allowed_domains() do
        [single] -> Map.put(params, "hd", single)
        _ -> params
      end

    @authorize_url <> "?" <> URI.encode_query(params)
  end

  @doc """
  Turn the `code` Google sent back into verified profile claims.
  """
  @spec fetch_claims(String.t(), String.t()) :: {:ok, claims()} | {:error, atom()}
  def fetch_claims(code, redirect_uri) when is_binary(code) and is_binary(redirect_uri) do
    with {:ok, access_token} <- exchange_code(code, redirect_uri),
         {:ok, claims} <- fetch_userinfo(access_token),
         :ok <- verify_claims(claims) do
      {:ok, claims}
    end
  end

  defp exchange_code(code, redirect_uri) do
    form = [
      code: code,
      client_id: client_id(),
      client_secret: client_secret(),
      redirect_uri: redirect_uri,
      grant_type: "authorization_code"
    ]

    case Req.post(req(), url: @token_url, form: form) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} when is_binary(token) ->
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "google token exchange failed #{status}: #{inspect(body) |> String.slice(0, 300)}"
        )

        {:error, :token_exchange_failed}

      {:error, reason} ->
        Logger.warning("google token exchange error: #{inspect(reason)}")
        {:error, :token_exchange_failed}
    end
  end

  defp fetch_userinfo(access_token) do
    case Req.get(req(), url: @userinfo_url, auth: {:bearer, access_token}) do
      {:ok, %{status: 200, body: %{"sub" => _} = claims}} ->
        {:ok, claims}

      {:ok, %{status: status}} ->
        Logger.warning("google userinfo failed #{status}")
        {:error, :userinfo_failed}

      {:error, reason} ->
        Logger.warning("google userinfo error: #{inspect(reason)}")
        {:error, :userinfo_failed}
    end
  end

  defp verify_claims(claims) do
    cond do
      not is_binary(claims["email"]) -> {:error, :no_email}
      claims["email_verified"] not in [true, "true"] -> {:error, :email_unverified}
      true -> verify_domain(claims)
    end
  end

  # Prefer Google's `hd` (hosted domain) claim, which only Workspace accounts
  # carry; fall back to the email's domain so a misconfigured tenant still
  # can't slip a consumer @gmail.com account through.
  defp verify_domain(claims) do
    case allowed_domains() do
      [] ->
        :ok

      domains ->
        hd = claims["hd"] |> to_string() |> String.downcase()
        email_domain = claims["email"] |> String.split("@") |> List.last() |> String.downcase()

        if hd in domains and email_domain in domains do
          :ok
        else
          {:error, :domain_not_allowed}
        end
    end
  end

  defp req do
    [receive_timeout: 15_000, retry: false]
    |> Keyword.merge(Keyword.get(config(), :req_options, []))
    |> Req.new()
  end

  defp client_id, do: config()[:client_id]
  defp client_secret, do: config()[:client_secret]

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp config, do: Application.get_env(:all_hands_sing_along, __MODULE__, [])
end
