defmodule Tama.MemoryResultContractTest do
  use ExUnit.Case, async: true

  @contract_path Path.expand("../../tama/graph/schemas/memory-contract.v1.json", __DIR__)
  @fixtures_path Path.expand("../../tama/graph/schemas/memory-fixtures.v1.json", __DIR__)

  setup_all do
    {:ok,
     contract: @contract_path |> File.read!() |> Jason.decode!(),
     fixtures: @fixtures_path |> File.read!() |> Jason.decode!()}
  end

  test "valid terminal publications and runtime envelopes satisfy their schemas", context do
    fixtures =
      context.fixtures["valid"] ++ context.fixtures["result_delivery"]["valid"]

    for fixture <- fixtures,
        fixture["schema"] in result_schema_names() do
      assert :ok == validate(context.contract, fixture),
             "expected #{fixture["id"]} to satisfy #{fixture["schema"]}"
    end
  end

  test "invalid delivery fixtures reject legacy and cross-operation payloads", context do
    fixtures =
      context.fixtures["invalid"] ++ context.fixtures["result_delivery"]["invalid"]

    for fixture <- fixtures,
        fixture["schema"] in result_schema_names() do
      assert {:error, _reason} = validate(context.contract, fixture),
             "expected #{fixture["id"]} to violate #{fixture["schema"]}"
    end
  end

  test "completed envelopes repeat the publication text at the transport level", context do
    fixtures =
      context.fixtures["valid"] ++ context.fixtures["result_delivery"]["valid"]

    for %{"schema" => "MessageResult", "value" => %{"status" => "completed"} = envelope} <-
          fixtures do
      assert envelope["text"] == envelope["result"]["text"]
      assert envelope["error"] == nil
    end
  end

  test "byte fixtures exercise Tama's authoritative UTF-8 limits", context do
    for fixture <- context.fixtures["result_delivery"]["byte_boundaries"] do
      repeated = String.duplicate(fixture["repeat"], fixture["count"])

      measured_bytes =
        case fixture["target"] do
          "text" ->
            byte_size(repeated)

          "serialized_publication" ->
            publication = recall_publication(repeated)

            assert :ok == validate_value(context.contract, "RecallResultPublication", publication)

            byte_size(Jason.encode!(publication))
        end

      assert fixture["max_bytes"] == runtime_limit(context.contract, fixture["target"])

      assert measured_bytes <= fixture["max_bytes"] == fixture["accepted"],
             "unexpected byte boundary result for #{fixture["id"]}"
    end
  end

  test "valid fixture publications fit Tama's serialized and visible-text budgets", context do
    fixtures =
      context.fixtures["valid"] ++ context.fixtures["result_delivery"]["valid"]

    for fixture <- fixtures,
        publication = publication_value(fixture),
        publication != nil do
      assert byte_size(Jason.encode!(publication)) <=
               runtime_limit(context.contract, "serialized_publication"),
             "expected #{fixture["id"]} to fit Tama's serialized publication budget"

      assert byte_size(publication["text"]) <= runtime_limit(context.contract, "text"),
             "expected #{fixture["id"]} to fit Tama's visible-text budget"
    end
  end

  test "operation-specific schemas remain distinct", %{contract: contract} do
    remember = contract["$defs"]["RememberResultPublication"]
    recall = contract["$defs"]["RecallResultPublication"]

    refute remember == recall

    assert contract["$defs"]["ResultPublication"]["oneOf"] == [
             %{"$ref" => "#/$defs/RememberResultPublication"},
             %{"$ref" => "#/$defs/RecallResultPublication"}
           ]
  end

  defp validate(contract, fixture) do
    validate_value(contract, fixture["schema"], fixture["value"])
  end

  defp validate_value(contract, schema_name, value) do
    schema =
      contract
      |> runtime_contract()
      |> Map.take(["$schema", "definitions"])
      |> Map.put("$ref", "#/definitions/#{schema_name}")

    schema
    |> JsonXema.new()
    |> JsonXema.validate(value)
  end

  defp runtime_contract(contract) do
    contract
    |> Map.put("$schema", "http://json-schema.org/draft-07/schema#")
    |> Jason.encode!()
    |> String.replace("\"$defs\":", "\"definitions\":")
    |> String.replace("#/$defs/", "#/definitions/")
    |> String.replace("\\\\u0000", "\\\\x{0000}")
    |> Jason.decode!()
  end

  defp result_schema_names do
    ~w(MessageResult ResultPublication RememberResultPublication RecallResultPublication)
  end

  defp publication_value(%{"schema" => schema, "value" => value})
       when schema in [
              "ResultPublication",
              "RememberResultPublication",
              "RecallResultPublication"
            ],
       do: value

  defp publication_value(%{
         "schema" => "MessageResult",
         "value" => %{"status" => "completed", "result" => result}
       }),
       do: result

  defp publication_value(_fixture), do: nil

  defp runtime_limit(contract, "text") do
    contract["$defs"]["ResultText"]["x-tama-max-utf8-bytes"]
  end

  defp runtime_limit(contract, "serialized_publication") do
    contract["$defs"]["RecallResultPublication"]["x-tama-max-serialized-bytes"]
  end

  defp recall_publication(body_excerpt) do
    %{
      "operation" => "recall",
      "outcome" => "answered",
      "claims" => recall_claims(),
      "sources" => recall_sources(body_excerpt),
      "indexing" => %{"pending_count" => 0, "failed_count" => 0},
      "text" => String.duplicate("x", 8_192)
    }
  end

  defp recall_claims do
    for claim_index <- 0..4 do
      %{
        "text" => String.duplicate("c", 400),
        "post_ids" => for(post_index <- 0..9, do: uuid(500 + claim_index * 10 + post_index))
      }
    end
  end

  defp recall_sources(body_excerpt) do
    tags =
      for index <- 0..3 do
        suffix = index |> Integer.to_string() |> String.pad_leading(2, "0")

        %{
          "namespace" => "project",
          "key" => String.duplicate("k", 98) <> suffix,
          "name" => String.duplicate("n", 253) <> suffix
        }
      end

    for source_index <- 0..9 do
      %{
        "post_id" => uuid(source_index + 1),
        "title" => String.duplicate("t", 255),
        "body_excerpt" => body_excerpt,
        "body_hash" => String.duplicate("a", 64),
        "kind" => "preference",
        "epistemic_status" => "user_stated",
        "approval" => "reported_approved",
        "source" => %{"channel" => "agent", "reference" => String.duplicate("r", 512)},
        "derived_from_post_ids" =>
          for(post_index <- 0..19, do: uuid(100 + source_index * 20 + post_index)),
        "recorded_at" => "2026-09-12T00:00:00Z",
        "occurred_at" => "2026-09-12T00:00:00Z",
        "effective_at" => "2026-09-12T00:00:00Z",
        "tags" => tags,
        "score" => 1.0,
        "indexing_status" => "ready"
      }
    end
  end

  defp uuid(value) do
    suffix = value |> Integer.to_string(16) |> String.pad_leading(12, "0")
    "01990000-0000-7000-8000-#{suffix}"
  end
end
