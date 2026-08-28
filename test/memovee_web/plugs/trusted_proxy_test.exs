defmodule MemoveeWeb.Plugs.TrustedProxyTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias MemoveeWeb.Plugs.TrustedProxy

  test "uses the forwarding chain when the socket peer is explicitly trusted" do
    conn =
      :get
      |> conn("/")
      |> Map.put(:remote_ip, {203, 0, 113, 10})
      |> put_req_header("x-forwarded-for", "198.51.100.24, 203.0.113.9")

    opts =
      TrustedProxy.init(
        headers: ["x-forwarded-for"],
        proxies: ["203.0.113.0/24"]
      )

    assert TrustedProxy.call(conn, opts).remote_ip == {198, 51, 100, 24}
  end

  test "ignores spoofed forwarding headers from an untrusted socket peer" do
    conn =
      :get
      |> conn("/")
      |> Map.put(:remote_ip, {198, 51, 100, 10})
      |> put_req_header("x-forwarded-for", "192.0.2.99")

    opts = TrustedProxy.init(proxies: ["203.0.113.10"])

    assert TrustedProxy.call(conn, opts).remote_ip == {198, 51, 100, 10}
  end

  test "uses the socket peer when no trusted proxies are configured" do
    conn =
      :get
      |> conn("/")
      |> Map.put(:remote_ip, {198, 51, 100, 11})
      |> put_req_header("x-forwarded-for", "192.0.2.100")

    assert [] = TrustedProxy.validate_proxies!([])

    assert TrustedProxy.call(conn, TrustedProxy.init(proxies: [])).remote_ip ==
             {198, 51, 100, 11}
  end

  test "supports exact IPv6 proxy addresses" do
    conn =
      :get
      |> conn("/")
      |> Map.put(:remote_ip, {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1})
      |> put_req_header("x-forwarded-for", "198.51.100.25")

    opts = TrustedProxy.init(proxies: ["2001:db8::1"])

    assert TrustedProxy.call(conn, opts).remote_ip == {198, 51, 100, 25}
  end

  test "rejects malformed trusted proxy configuration" do
    conn = :get |> conn("/") |> Map.put(:remote_ip, {203, 0, 113, 10})
    opts = TrustedProxy.init(proxies: ["not-an-address"])

    assert_raise ArgumentError, ~r/invalid trusted proxy/, fn ->
      TrustedProxy.call(conn, opts)
    end
  end
end
