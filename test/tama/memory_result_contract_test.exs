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
          "text" -> byte_size(repeated)
          "serialized_publication" -> byte_size(Jason.encode!(%{"text" => repeated}))
        end

      assert measured_bytes <= fixture["max_bytes"] == fixture["accepted"],
             "unexpected byte boundary result for #{fixture["id"]}"
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
    schema =
      contract
      |> runtime_contract()
      |> Map.take(["$schema", "definitions"])
      |> Map.put("$ref", "#/definitions/#{fixture["schema"]}")

    schema
    |> JsonXema.new()
    |> JsonXema.validate(fixture["value"])
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
end
