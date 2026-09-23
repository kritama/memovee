defmodule Memovee.Tama.RememberCorporaTest do
  use ExUnit.Case, async: true

  import Memovee.Tama.RememberCorporaFixtures

  @graph_root Path.expand("../../tama/graph", __DIR__)

  describe "save result rendering" do
    test "publishes a newly created Post receipt" do
      result =
        tooling("memory_post_create", "call-save", 201, %{"data" => %{"receipt" => receipt()}})
        |> classify()

      assert result["kind"] == "save"
      assert finish_save(result)["outcome"] == "saved"
    end

    test "publishes an idempotent replay receipt" do
      replayed_receipt = Map.put(receipt(), "replayed", true)

      result =
        tooling("memory_post_create", "call-replay", 200, %{
          "data" => %{"receipt" => replayed_receipt}
        })
        |> classify()
        |> finish_save()

      assert result["replayed"] == true
    end

    test "reports transport ambiguity without claiming the save failed" do
      result =
        tooling("memory_post_create", "call-timeout", 0, %{
          "error" => %{"outcome" => "unknown"}
        })
        |> classify()
        |> finish_save()

      assert get_in(result, ["error", "code"]) == "save_unconfirmed"
    end

    test "reports retryable HTTP failure" do
      result =
        tooling("memory_post_create", "call-503", 503, %{"error" => "busy"})
        |> classify()
        |> finish_save()

      assert get_in(result, ["error", "code"]) == "save_unavailable"
    end

    test "rejects a malformed success body" do
      result =
        tooling("memory_post_create", "call-bad", 201, %{"data" => %{}})
        |> classify()
        |> finish_save()

      assert get_in(result, ["error", "code"]) == "invalid_tool_result"
    end

    test "rejects a receipt without tag IDs" do
      missing_tags_receipt = Map.delete(receipt(), "tag_ids")

      result =
        tooling("memory_post_create", "call-missing-tags", 201, %{
          "data" => %{"receipt" => missing_tags_receipt}
        })
        |> classify()
        |> finish_save()

      assert get_in(result, ["error", "code"]) == "invalid_tool_result"
    end

    test "rejects invalid receipt field types" do
      wrong_type_receipt = %{receipt() | "post_id" => 123, "tag_ids" => [456]}

      result =
        tooling("memory_post_create", "call-wrong-types", 201, %{
          "data" => %{"receipt" => wrong_type_receipt}
        })
        |> classify()
        |> finish_save()

      assert get_in(result, ["error", "code"]) == "invalid_tool_result"
    end
  end

  describe "clarification rendering" do
    test "publishes a valid memo question" do
      result = tooling("memo", "call-memo", 200, memo_payload()) |> classify()

      assert result["kind"] == "clarification"
      assert finish_clarification(result)["outcome"] == "clarification_required"
    end

    test "rejects an oversized memo question" do
      result =
        tooling("memo", "call-memo", 200, memo_payload())
        |> classify()
        |> put_in(["payload", "summary"], String.duplicate("x", 401))
        |> finish_clarification()

      assert get_in(result, ["error", "code"]) == "invalid_tool_result"
    end

    test "rejects a non-string memo question" do
      result =
        tooling("memo", "call-memo", 200, memo_payload())
        |> classify()
        |> put_in(["payload", "summary"], 123)
        |> finish_clarification()

      assert get_in(result, ["error", "code"]) == "invalid_tool_result"
    end
  end

  describe "tool call correlation" do
    test "rejects a mismatched call ID" do
      result =
        tooling("memory_post_create", "call-expected", 201, %{
          "data" => %{"receipt" => receipt()}
        })
        |> put_in(["messages", Access.at(1), "tool_call_id"], "call-other")
        |> classify()

      assert result["kind"] == "invalid"
    end

    test "rejects multiple calls in one assistant message" do
      result =
        tooling("memory_post_create", "call-one", 201, %{
          "data" => %{"receipt" => receipt()}
        })
        |> update_in(["messages", Access.at(0), "tool_calls"], fn calls ->
          calls ++ [%{"id" => "call-two", "function" => %{"name" => "memory_post_create"}}]
        end)
        |> classify()

      assert result["kind"] == "invalid"
    end

    test "rejects duplicate responses to one call" do
      result =
        tooling("memory_post_create", "call-one", 201, %{
          "data" => %{"receipt" => receipt()}
        })
        |> update_in(["messages"], fn messages -> messages ++ [List.last(messages)] end)
        |> classify()

      assert result["kind"] == "invalid"
    end
  end

  defp classify(data), do: render("memory-write/remember-tool-result.liquid", data)
  defp finish_save(data), do: render("remember-save/remember-save-result.liquid", data)

  defp finish_clarification(data),
    do: render("remember-clarification/remember-clarification-result.liquid", data)

  defp render(relative_path, data) do
    @graph_root
    |> Path.join(relative_path)
    |> File.read!()
    |> Solid.parse!()
    |> Solid.render!(%{"data" => data, "inputs" => %{}},
      custom_filters: &json_filter/2,
      strict_filters: true
    )
    |> to_string()
    |> Jason.decode!()
  end

  # Tama 0.15.0's Tama.Concepts.Render.Filters.json/1 delegates to Jason.encode!/1.
  defp json_filter("json", [value]), do: {:ok, Jason.encode!(value)}
  defp json_filter(_, _), do: :error
end
