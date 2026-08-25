defimpl Eventful.Transit, for: Memovee.Memory.Projection do
  alias Memovee.Memory.Projection.Event

  def perform(projection, actor, event_name, options \\ []) do
    Event.handle(projection, actor, %{
      domain: Keyword.get(options, :domain, "transitions"),
      name: event_name,
      comment: Keyword.get(options, :comment),
      parameters: Keyword.get(options, :parameters, %{})
    })
  end
end
