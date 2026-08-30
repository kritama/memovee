defmodule Memovee.OAuth.Client.ReplayStoreTest do
  use Memovee.DataCase, async: false

  alias Memovee.OAuth.Client.ReplayStore

  test "claims each client assertion digest exactly once" do
    digest = TamaOAuth.Crypto.digest("unique-client-assertion")
    expires_at = DateTime.add(DateTime.utc_now(:microsecond), 5, :minute)

    assert :ok = ReplayStore.claim(digest, expires_at)
    assert {:error, :replayed} = ReplayStore.claim(digest, expires_at)
  end
end
