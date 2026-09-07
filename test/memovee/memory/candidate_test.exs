defmodule Memovee.Memory.CandidateTest do
  use ExUnit.Case, async: true
  alias Memovee.Memory.Candidate

  test "UTF-8 byte limits preserve exact text" do
    assert {:ok, _} = Candidate.validate(%{"body" => String.duplicate("🙂", 8192)}, false)

    assert {:error, :invalid_candidate} =
             Candidate.validate(%{"body" => String.duplicate("🙂", 8193)}, false)

    assert {:error, :invalid_candidate} =
             Candidate.validate(%{"body" => String.duplicate("a", 32_769)}, false)
  end

  test "reserved metadata keys are rejected at any nesting depth" do
    for key <-
          ~w(owner_actor_id actor_id created_by_actor_id current_state current_state_version ingestion_id origin_identifier) do
      attrs = %{"body" => "source", "metadata" => %{"nested" => [%{key => "forged"}]}}
      assert {:error, :invalid_candidate} = Candidate.validate(attrs, false)
    end

    assert {:ok, _} =
             Candidate.validate(
               %{"body" => "source", "metadata" => %{"arbitrary" => [1, true, nil]}},
               false
             )
  end

  test "generated keys, explicit keys and normalized deduplication" do
    attrs = %{
      "body" => "source",
      "tags" => [
        %{"namespace" => " Tool ", "name" => "Org/Tool Name"},
        %{"namespace" => "project", "key" => " Kritama.Memovee ", "name" => "Memovee"},
        %{"namespace" => "project", "key" => "kritama.memovee", "name" => "Duplicate"},
        %{"namespace" => "topic", "name" => "🙂"}
      ]
    }

    assert {:ok, {_, tags}} = Candidate.validate(attrs, false)
    assert length(tags) == 3
    assert Enum.any?(tags, &(&1["key"] == "org.tool-name"))
    assert Enum.any?(tags, &(&1["key"] == "kritama.memovee"))
    expected = "tag-" <> String.slice(Candidate.hash("🙂"), 0, 12)
    assert Enum.any?(tags, &(&1["key"] == expected))
  end
end
