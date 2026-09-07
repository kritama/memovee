tasks = Tama.Perception.Module.valid_tasks()
required = ["tama/agentic/result", "tama/concepts/render", "tama/concepts/dispatch"]
caller_fields = Tama.Actions.Caller.Params.__schema__(:fields)
generate_fields = Tama.Agentic.Generate.Params.__schema__(:fields)
queue_limits = [{:"memory-interactive", 4}, {:"memory-index", 2}]

ready =
  Enum.all?(required, &(&1 in tasks)) and
    :capture_transport_errors in caller_fields and :max_http_retries in caller_fields and
    :max_generation_attempts in generate_fields and
    Enum.all?(queue_limits, fn {queue, limit} ->
      case Oban.check_queue(queue: queue) do
        %{limit: ^limit, paused: false} -> true
        _ -> false
      end
    end)

IO.puts(if ready, do: "MEMORY_RUNTIME_READY", else: "MEMORY_RUNTIME_BLOCKED")
