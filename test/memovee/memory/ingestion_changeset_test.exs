defmodule Memovee.Memory.IngestionChangesetTest do
  use ExUnit.Case, async: true
  alias Ecto.Changeset
  alias Memovee.Memory.Ingestion

  test "preserves exact source bytes and derives its hash without casting trusted fields" do
    owner_id = Ecto.UUID.generate(version: 7)
    actor_id = Ecto.UUID.generate(version: 7)

    ingestion = %Ingestion{
      owner_actor_id: owner_id,
      created_by_actor_id: actor_id,
      origin_identifier: "source:1"
    }

    content = "  Original source 🙂\n"

    changeset =
      Ingestion.changeset(ingestion, %{
        original_content: content,
        owner_actor_id: Ecto.UUID.generate(version: 7),
        created_by_actor_id: Ecto.UUID.generate(version: 7),
        origin_identifier: "forged",
        source_hash: "forged",
        post_id: Ecto.UUID.generate(version: 7),
        saved_receipt: %{"forged" => true}
      })

    assert changeset.valid?
    assert Changeset.get_field(changeset, :original_content) == content

    assert Changeset.get_field(changeset, :source_hash) ==
             Base.encode16(:crypto.hash(:sha256, content), case: :lower)

    assert Changeset.get_field(changeset, :owner_actor_id) == owner_id
    assert Changeset.get_field(changeset, :created_by_actor_id) == actor_id
    assert Changeset.get_field(changeset, :origin_identifier) == "source:1"
    assert Changeset.get_field(changeset, :post_id) == nil
    assert Changeset.get_field(changeset, :saved_receipt) == nil
  end

  test "rejects missing trusted fields and invalid source text" do
    refute Ingestion.changeset(%Ingestion{}, %{original_content: "source"}).valid?

    ingestion = %Ingestion{
      owner_actor_id: Ecto.UUID.generate(version: 7),
      created_by_actor_id: Ecto.UUID.generate(version: 7),
      origin_identifier: "source:1"
    }

    for content <- [nil, "", " \n\t", <<255>>, 123] do
      refute Ingestion.changeset(ingestion, %{original_content: content}).valid?
    end
  end
end
