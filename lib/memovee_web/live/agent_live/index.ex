defmodule MemoveeWeb.AgentLive.Index do
  use MemoveeWeb, :live_view

  alias Memovee.Accounts

  @impl true
  def mount(_params, _session, socket) do
    agents = Accounts.list_owned_agents(socket.assigns.current_scope.actor)
    {:ok, stream(socket, :agents, agents)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="agents-index" class="mx-auto max-w-5xl space-y-8">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
          <div class="space-y-2">
            <p class="text-xs font-semibold uppercase tracking-[0.22em] text-sky-700">Automation</p>
            <h1 class="text-3xl font-semibold tracking-tight text-slate-950">Your agents</h1>
            <p class="max-w-2xl text-sm leading-6 text-slate-600">
              Create isolated machine identities and rotate their API credentials without affecting your account.
            </p>
          </div>
          <.link
            id="new-agent-link"
            navigate={~p"/agents/new"}
            class="inline-flex items-center justify-center gap-2 rounded-xl bg-slate-950 px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:-translate-y-0.5 hover:bg-sky-950 focus:outline-none focus:ring-2 focus:ring-sky-500 focus:ring-offset-2"
          >
            <.icon name="hero-plus" class="size-4" /> New agent
          </.link>
        </div>

        <div
          id="agents"
          phx-update="stream"
          class="grid gap-4 md:grid-cols-2"
        >
          <div
            id="agents-empty"
            class="hidden only:flex min-h-56 flex-col items-center justify-center rounded-2xl border border-dashed border-slate-300 bg-white p-8 text-center md:col-span-2"
          >
            <div class="mb-4 rounded-2xl bg-sky-50 p-3 text-sky-700">
              <.icon name="hero-cpu-chip" class="size-6" />
            </div>
            <h2 class="font-semibold text-slate-950">No agents yet</h2>
            <p class="mt-1 max-w-sm text-sm text-slate-600">
              Create an agent before issuing its first credential.
            </p>
          </div>

          <.link
            :for={{id, agent} <- @streams.agents}
            id={id}
            navigate={~p"/agents/#{agent.id}"}
            class="group rounded-2xl border border-slate-200 bg-white p-5 shadow-sm transition hover:-translate-y-0.5 hover:border-sky-300 hover:shadow-md"
          >
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0">
                <p class="truncate font-semibold text-slate-950">{agent.identifier}</p>
                <p class="mt-1 truncate font-mono text-xs text-slate-500">{agent.id}</p>
              </div>
              <span class={[
                "rounded-full px-2.5 py-1 text-xs font-medium",
                if(agent.current_state == "active",
                  do: "bg-emerald-50 text-emerald-700",
                  else: "bg-slate-100 text-slate-600"
                )
              ]}>
                {agent.current_state}
              </span>
            </div>
            <div class="mt-6 flex items-center justify-between text-sm font-medium text-sky-800">
              Manage credentials
              <.icon
                name="hero-arrow-right"
                class="size-4 transition group-hover:translate-x-1"
              />
            </div>
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
