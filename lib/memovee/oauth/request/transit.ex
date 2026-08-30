defimpl Eventful.Transit, for: Memovee.OAuth.Request do
  alias Memovee.OAuth.Request.Event

  def perform(request, actor, event_name, options \\ []) do
    Event.handle(request, actor, %{
      domain: Keyword.get(options, :domain, "transitions"),
      name: event_name,
      comment: Keyword.get(options, :comment),
      parameters: Keyword.get(options, :parameters, %{})
    })
  end
end
