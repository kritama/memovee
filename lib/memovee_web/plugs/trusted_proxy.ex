defmodule MemoveeWeb.Plugs.TrustedProxy do
  @moduledoc """
  Resolves the originating address only when the socket peer is explicitly trusted.
  """

  @behaviour Plug

  import Bitwise

  @impl Plug
  def init(opts) do
    %{
      headers: Keyword.get(opts, :headers, ["x-forwarded-for"]),
      proxies: Keyword.fetch!(opts, :proxies)
    }
  end

  @impl Plug
  def call(conn, %{headers: headers, proxies: proxies_option}) do
    proxies = resolve(proxies_option)

    if trusted?(conn.remote_ip, proxies) do
      remote_ip_options = RemoteIp.init(headers: headers, proxies: proxies)
      RemoteIp.call(conn, remote_ip_options)
    else
      conn
    end
  end

  def configured_proxies do
    :memovee
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:proxies, [])
  end

  def validate_proxies!(proxies) when is_list(proxies) do
    Enum.each(proxies, &parse_network!/1)
    proxies
  end

  defp resolve({module, function, arguments}), do: apply(module, function, arguments)
  defp resolve(proxies) when is_list(proxies), do: proxies

  defp trusted?(remote_ip, proxies) do
    Enum.any?(proxies, fn proxy ->
      proxy
      |> parse_network!()
      |> contains?(remote_ip)
    end)
  end

  defp parse_network!(network) when is_binary(network) do
    network = String.trim(network)
    {address, prefix} = split_network(network)

    with {:ok, parsed_address} <- :inet.parse_strict_address(String.to_charlist(address)),
         {width, encoded_address} <- encode(parsed_address),
         true <- prefix in 0..width do
      {width, encoded_address, prefix}
    else
      _error -> raise ArgumentError, "invalid trusted proxy address or CIDR: #{inspect(network)}"
    end
  end

  defp split_network(network) do
    case String.split(network, "/", parts: 2) do
      [address] -> {address, address_width(address)}
      [address, prefix] -> {address, parse_prefix!(network, prefix)}
    end
  end

  defp address_width(address) do
    if String.contains?(address, ":"), do: 128, else: 32
  end

  defp parse_prefix!(network, prefix) do
    case Integer.parse(prefix) do
      {value, ""} -> value
      _error -> raise ArgumentError, "invalid trusted proxy address or CIDR: #{inspect(network)}"
    end
  end

  defp contains?({width, network, prefix}, remote_ip) do
    case encode_for_width(remote_ip, width) do
      {^width, address} -> address >>> (width - prefix) == network >>> (width - prefix)
      {_other_width, _address} -> false
    end
  end

  defp encode_for_width({0, 0, 0, 0, 0, 0xFFFF, high, low}, 32) do
    {32, high <<< 16 ||| low}
  end

  defp encode_for_width(remote_ip, _width), do: encode(remote_ip)

  defp encode({a, b, c, d}) do
    {32, a <<< 24 ||| b <<< 16 ||| c <<< 8 ||| d}
  end

  defp encode({a, b, c, d, e, f, g, h}) do
    encoded =
      [a, b, c, d, e, f, g, h]
      |> Enum.reduce(0, fn segment, accumulator -> accumulator <<< 16 ||| segment end)

    {128, encoded}
  end
end
