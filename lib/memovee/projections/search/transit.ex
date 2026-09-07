defimpl Eventful.Transit, for: Memovee.Projections.Search do
  alias Memovee.Projections.Search.Event

  def perform(projection, actor, event_name, options \\ []) do
    Event.handle(projection, actor, %{
      domain: Keyword.get(options, :domain, "transitions"),
      name: event_name,
      comment: Keyword.get(options, :comment),
      parameters: Keyword.get(options, :parameters, %{})
    })
  end
end
