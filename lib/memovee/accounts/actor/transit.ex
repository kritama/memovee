defimpl Eventful.Transit, for: Memovee.Accounts.Actor do
  alias Memovee.Accounts.Actor.Event

  def perform(actor, performing_actor, event_name, options \\ []) do
    Event.handle(actor, performing_actor, %{
      domain: Keyword.get(options, :domain, "transitions"),
      name: event_name,
      comment: Keyword.get(options, :comment),
      parameters: Keyword.get(options, :parameters, %{})
    })
  end
end
