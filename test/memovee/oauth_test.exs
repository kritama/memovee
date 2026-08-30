defmodule Memovee.OAuthTest do
  use ExUnit.Case, async: true

  alias Memovee.OAuth

  test "accepts an HTTPS origin as the issuer" do
    assert :ok = OAuth.validate_issuer!("https://memovee.example:444", scheme: "https")
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
        OAuth.validate_issuer!(issuer, scheme: "https")
      end
    end
  end

  test "rejects an issuer with the wrong scheme or no host" do
    for issuer <- ["http://memovee.example", "https:memovee.example"] do
      assert_raise ArgumentError, fn ->
        OAuth.validate_issuer!(issuer, scheme: "https")
      end
    end
  end
end
