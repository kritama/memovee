defmodule MemoveeWeb.AgentLive.New do
  use MemoveeWeb, :live_view

  alias Memovee.Accounts
  alias Memovee.Accounts.Actor

  @impl true
  def mount(_params, _session, socket) do
    changeset = Accounts.change_agent(%Actor{})
    {:ok, assign(socket, form: to_form(changeset, as: :agent))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="new-agent" class="mx-auto max-w-xl">
        <.link
          id="back-to-agents-link"
          navigate={~p"/agents"}
          class="mb-6 inline-flex items-center gap-2 text-sm font-medium text-slate-600 transition hover:text-slate-950"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Back to agents
        </.link>

        <div class="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm sm:p-8">
          <div class="mb-8 space-y-2">
            <p class="text-xs font-semibold uppercase tracking-[0.22em] text-sky-700">New identity</p>
            <h1 class="text-2xl font-semibold tracking-tight text-slate-950">Create an agent</h1>
            <p class="text-sm leading-6 text-slate-600">
              The identifier is stable, unique, and normalized to lowercase.
            </p>
          </div>

          <.form
            for={@form}
            id="agent-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-5"
          >
            <.input
              field={@form[:identifier]}
              type="text"
              label="Agent identifier"
              autocomplete="off"
              placeholder="media-indexer"
              required
              class="w-full rounded-xl border border-slate-300 bg-white px-3 py-2.5 text-slate-950 outline-none transition placeholder:text-slate-400 focus:border-sky-500 focus:ring-4 focus:ring-sky-100"
              error_class="border-rose-400 focus:border-rose-500 focus:ring-rose-100"
            />
            <button
              id="create-agent-button"
              type="submit"
              phx-disable-with="Creating agent…"
              class="inline-flex w-full items-center justify-center rounded-xl bg-slate-950 px-4 py-3 text-sm font-semibold text-white transition hover:bg-sky-950 disabled:cursor-wait disabled:opacity-70"
            >
              Create agent
            </button>
          </.form>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"agent" => params}, socket) do
    changeset =
      %Actor{}
      |> Accounts.change_agent(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :agent))}
  end

  def handle_event("save", %{"agent" => params}, socket) do
    case Accounts.create_agent(socket.assigns.current_scope.actor, params) do
      {:ok, agent} ->
        {:noreply,
         socket
         |> put_flash(:info, "Agent created. You can now issue its first credential.")
         |> push_navigate(to: ~p"/agents/#{agent.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :agent, action: :insert))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Agent could not be created.")}
    end
  end
end
