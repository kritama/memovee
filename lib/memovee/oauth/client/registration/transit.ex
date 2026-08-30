defimpl Eventful.Transit, for: Memovee.OAuth.Client.Registration do
  alias Memovee.OAuth.Client.Registration.Event

  def perform(registration, actor, event_name, options \\ []) do
    Event.handle(registration, actor, %{
      domain: Keyword.get(options, :domain, "transitions"),
      name: event_name,
      comment: Keyword.get(options, :comment),
      parameters: Keyword.get(options, :parameters, %{})
    })
  end
end
