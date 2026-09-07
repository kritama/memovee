defimpl Eventful.Transit, for: Memovee.Memory.ProjectionJob do
  alias Memovee.Memory.ProjectionJob.Event

  def perform(projection, actor, event_name, options \\ []) do
    Event.handle(projection, actor, %{
      domain: Keyword.get(options, :domain, "transitions"),
      name: event_name,
      comment: Keyword.get(options, :comment),
      parameters: Keyword.get(options, :parameters, %{})
    })
  end
end
