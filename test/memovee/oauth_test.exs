defmodule Memovee.OAuthTest do
  use ExUnit.Case, async: true

  alias Memovee.OAuth

  test "accepts an HTTPS origin as the issuer" do
    assert :ok = OAuth.validate_issuer!("https://memovee.example:444")
  end

  test "rejects issuer components that are not represented in OAuth routes" do
    invalid_issuers = [
      "https://memovee.example/",
      "https://memovee.example/oauth",
      "https://memovee.example?tenant=one",
      "https://memovee.example#oauth",
      "https://user@memovee.example"
    ]

    for issuer <- invalid_issuers do
      assert_raise ArgumentError, fn ->
        OAuth.validate_issuer!(issuer)
      end
    end
  end

  test "rejects an issuer with the wrong scheme or no host" do
    for issuer <- ["http://memovee.example", "https:memovee.example"] do
      assert_raise ArgumentError, fn ->
        OAuth.validate_issuer!(issuer)
      end
    end
  end

  test "validates routed resource and remote JWKS HTTPS URIs" do
    assert :ok =
             OAuth.validate_https_uri!("https://tama.example/mcp/app",
               path: "/mcp/app",
               query: false
             )

    assert :ok = OAuth.validate_https_uri!("https://tama.example/jwks.json?version=2")
  end

  test "rejects malformed or unsafe production HTTPS URIs" do
    for value <- [
          "https://",
          "https://?key=value",
          "http://tama.example/mcp/app",
          "https://user@tama.example/mcp/app",
          "https://tama.example/mcp/app#keys"
        ] do
      assert_raise ArgumentError, fn -> OAuth.validate_https_uri!(value) end
    end

    assert_raise ArgumentError, fn ->
      OAuth.validate_https_uri!("https://tama.example", path: :required)
    end

    assert_raise ArgumentError, fn ->
      OAuth.validate_https_uri!("https://tama.example/mcp/other", path: "/mcp/app")
    end

    assert_raise ArgumentError, fn ->
      OAuth.validate_https_uri!("https://tama.example/mcp/app?tenant=one", query: false)
    end
  end
end
