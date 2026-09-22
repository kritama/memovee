graph_root = Path.expand("../graph", __DIR__)

render = fn relative_path, data ->
  graph_root
  |> Path.join(relative_path)
  |> File.read!()
  |> Solid.parse!()
  |> Solid.render!(%{"data" => data, "inputs" => %{}},
    custom_filters: Tama.Concepts.Render.Filters,
    strict_filters: true
  )
  |> to_string()
  |> Jason.decode!()
end

assert_equal = fn actual, expected, label ->
  if actual != expected do
    raise "#{label}: expected #{inspect(expected)}, got #{inspect(actual)}"
  end
end

receipt = %{
  "post_id" => "01990000-0000-7000-8000-000000000001",
  "body_hash" => String.duplicate("a", 64),
  "tag_ids" => ["01990000-0000-7000-8000-000000000002"],
  "indexing_status" => "pending",
  "replayed" => false
}

tooling = fn name, id, code, payload ->
  %{
    "messages" => [
      %{
        "role" => "assistant",
        "tool_calls" => [%{"id" => id, "function" => %{"name" => name}}]
      },
      %{
        "role" => "tool",
        "name" => name,
        "tool_call_id" => id,
        "code" => code,
        "content" => Jason.encode!(payload)
      }
    ]
  }
end

classify = fn data -> render.("memory-write/remember-tool-result.liquid", data) end
finish_save = fn data -> render.("remember-save/remember-save-result.liquid", data) end

finish_clarification = fn data ->
  render.("remember-clarification/remember-clarification-result.liquid", data)
end

saved =
  classify.(
    tooling.("memory_post_create", "call-save", 201, %{
      "data" => %{"receipt" => receipt}
    })
  )

assert_equal.(saved["kind"], "save", "saved classification")
assert_equal.(finish_save.(saved)["outcome"], "saved", "created receipt")

replayed_receipt = Map.put(receipt, "replayed", true)

replayed =
  classify.(
    tooling.("memory_post_create", "call-replay", 200, %{
      "data" => %{"receipt" => replayed_receipt}
    })
  )

assert_equal.(finish_save.(replayed)["replayed"], true, "replayed receipt")

uncertain =
  classify.(
    tooling.("memory_post_create", "call-timeout", 0, %{
      "error" => %{"outcome" => "unknown"}
    })
  )

assert_equal.(
  get_in(finish_save.(uncertain), ["error", "code"]),
  "save_unconfirmed",
  "transport ambiguity"
)

unavailable =
  classify.(tooling.("memory_post_create", "call-503", 503, %{"error" => "busy"}))

assert_equal.(
  get_in(finish_save.(unavailable), ["error", "code"]),
  "save_unavailable",
  "retryable HTTP failure"
)

malformed =
  classify.(tooling.("memory_post_create", "call-bad", 201, %{"data" => %{}}))

assert_equal.(
  get_in(finish_save.(malformed), ["error", "code"]),
  "invalid_tool_result",
  "malformed success"
)

missing_tags_receipt = Map.delete(receipt, "tag_ids")

missing_tags =
  classify.(
    tooling.("memory_post_create", "call-missing-tags", 201, %{
      "data" => %{"receipt" => missing_tags_receipt}
    })
  )

assert_equal.(
  get_in(finish_save.(missing_tags), ["error", "code"]),
  "invalid_tool_result",
  "missing tag list"
)

wrong_type_receipt = %{receipt | "post_id" => 123, "tag_ids" => [456]}

wrong_types =
  classify.(
    tooling.("memory_post_create", "call-wrong-types", 201, %{
      "data" => %{"receipt" => wrong_type_receipt}
    })
  )

assert_equal.(
  get_in(finish_save.(wrong_types), ["error", "code"]),
  "invalid_tool_result",
  "wrong receipt types"
)

memo_payload = %{
  "target" => "response",
  "reason" => "clarification_required",
  "summary" => "Which project should this preference apply to?",
  "_context" => %{"tool_call_id" => "call-memo"}
}

memo = classify.(tooling.("memo", "call-memo", 200, memo_payload))
assert_equal.(memo["kind"], "clarification", "memo classification")

assert_equal.(
  finish_clarification.(memo)["outcome"],
  "clarification_required",
  "valid clarification"
)

bad_memo = put_in(memo, ["payload", "summary"], String.duplicate("x", 401))

assert_equal.(
  get_in(finish_clarification.(bad_memo), ["error", "code"]),
  "invalid_tool_result",
  "oversized clarification"
)

wrong_type_memo = put_in(memo, ["payload", "summary"], 123)

assert_equal.(
  get_in(finish_clarification.(wrong_type_memo), ["error", "code"]),
  "invalid_tool_result",
  "wrong clarification type"
)

mismatched =
  "memory_post_create"
  |> tooling.("call-expected", 201, %{"data" => %{"receipt" => receipt}})
  |> put_in(["messages", Access.at(1), "tool_call_id"], "call-other")

assert_equal.(classify.(mismatched)["kind"], "invalid", "mismatched call identity")

multiple =
  "memory_post_create"
  |> tooling.("call-one", 201, %{"data" => %{"receipt" => receipt}})
  |> update_in(["messages", Access.at(0), "tool_calls"], fn calls ->
    calls ++ [%{"id" => "call-two", "function" => %{"name" => "memory_post_create"}}]
  end)

assert_equal.(classify.(multiple)["kind"], "invalid", "multiple calls")

IO.puts("remember corpus fixtures: 13 passed")
