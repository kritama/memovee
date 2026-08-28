defimpl Eventful.Transit, for: Memovee.OAuth.Grant do
  alias Memovee.OAuth.Grant.Event

  def perform(grant, actor, event_name, options \\ []) do
    Event.handle(grant, actor, %{
      domain: Keyword.get(options, :domain, "transitions"),
      name: event_name,
      comment: Keyword.get(options, :comment),
      parameters: Keyword.get(options, :parameters, %{})
    })
  end
end
