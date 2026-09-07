defmodule Memovee.Projections.Indexing.Worker do
  @moduledoc "Oban entry point for memory indexing. The queue remains paused until #13 implements execution."
  use Oban.Worker, queue: :memory_projection, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Never acknowledge indexing success before the graph and Redis pipeline exists.
    {:error, :projection_pipeline_not_implemented}
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    Enum.at([1, 5, 30, 120], min(max(attempt - 1, 0), 3))
  end
end
