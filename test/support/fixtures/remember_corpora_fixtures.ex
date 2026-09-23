defmodule Memovee.Tama.RememberCorporaFixtures do
  @moduledoc false

  def receipt do
    %{
      "post_id" => "01990000-0000-7000-8000-000000000001",
      "body_hash" => String.duplicate("a", 64),
      "tag_ids" => ["01990000-0000-7000-8000-000000000002"],
      "indexing_status" => "pending",
      "replayed" => false
    }
  end

  def tooling(name, id, code, payload) do
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

  def memo_payload do
    %{
      "target" => "response",
      "reason" => "clarification_required",
      "summary" => "Which project should this preference apply to?",
      "_context" => %{"tool_call_id" => "call-memo"}
    }
  end
end
