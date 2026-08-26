defmodule MemoveeWeb.Console.AgentLive.Show do
  use MemoveeWeb, :live_view

  alias Memovee.Accounts
  alias Memovee.Accounts.Agent

  @expiry_days ~w(30 90 365)

  @impl true
  def mount(%{"id" => agent_id}, _session, socket) do
    owner = socket.assigns.current_scope.actor

    case Accounts.get_agent_with_api_tokens(owner, agent_id) do
      {:ok, %{agent: agent, tokens: tokens}} ->
        {:ok,
         socket
         |> assign(:agent, agent)
         |> assign(:credential, nil)
         |> assign(:token_form, token_form())
         |> stream(:tokens, tokens), temporary_assigns: [credential: nil]}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Agent was not found.")
         |> push_navigate(to: ~p"/console/agents")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="agent-show" class="mx-auto max-w-5xl space-y-8">
        <div>
          <.link
            id="back-to-agents-link"
            navigate={~p"/console/agents"}
            class="mb-5 inline-flex items-center gap-2 text-sm font-medium text-slate-600 transition hover:text-slate-950"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Back to agents
          </.link>

          <div class="flex flex-col gap-5 rounded-3xl bg-slate-950 p-6 text-white shadow-xl shadow-slate-200 sm:flex-row sm:items-center sm:justify-between sm:p-8">
            <div class="min-w-0">
              <div class="mb-3 flex items-center gap-3">
                <span class="rounded-full bg-white/10 px-2.5 py-1 text-xs font-medium text-sky-100">
                  {@agent.current_state}
                </span>
                <span class="text-xs font-medium uppercase tracking-[0.2em] text-slate-400">Agent</span>
              </div>
              <h1 class="truncate text-3xl font-semibold tracking-tight">{@agent.identifier}</h1>
              <p class="mt-2 truncate font-mono text-xs text-slate-400">{@agent.id}</p>
            </div>

            <button
              :if={@agent.current_state == "active"}
              id="deactivate-agent-button"
              type="button"
              phx-click="deactivate"
              data-confirm="Deactivate this agent? Every credential will stop working immediately."
              class="inline-flex items-center justify-center rounded-xl border border-rose-300/30 bg-rose-400/10 px-4 py-2.5 text-sm font-semibold text-rose-100 transition hover:bg-rose-400/20"
            >
              Deactivate agent
            </button>
            <button
              :if={@agent.current_state == "inactive"}
              id="activate-agent-button"
              type="button"
              phx-click="activate"
              class="inline-flex items-center justify-center rounded-xl bg-emerald-400 px-4 py-2.5 text-sm font-semibold text-emerald-950 transition hover:bg-emerald-300"
            >
              Reactivate agent
            </button>
          </div>
        </div>

        <div
          :if={@credential}
          id="api-secret"
          class="rounded-2xl border border-amber-300 bg-amber-50 p-5 shadow-sm"
        >
          <div class="flex items-start gap-3">
            <.icon name="hero-key" class="mt-0.5 size-5 shrink-0 text-amber-700" />
            <div class="min-w-0 flex-1">
              <h2 class="font-semibold text-amber-950">Copy this credential now</h2>
              <p class="mt-1 text-sm text-amber-900/75">
                The secret is shown once. Store it in your secret manager before leaving this response.
              </p>
              <dl class="mt-4 space-y-3">
                <div>
                  <dt class="text-xs font-semibold uppercase tracking-wide text-amber-800">
                    Client ID
                  </dt>
                  <dd
                    id="api-client-id"
                    class="mt-1 break-all rounded-lg bg-white/70 p-3 font-mono text-sm text-slate-950"
                  >
                    {@credential.client_id}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs font-semibold uppercase tracking-wide text-amber-800">
                    Client secret
                  </dt>
                  <dd
                    id="api-client-secret"
                    class="mt-1 break-all rounded-lg bg-white/70 p-3 font-mono text-sm text-slate-950"
                  >
                    {@credential.client_secret}
                  </dd>
                </div>
              </dl>
              <button
                id="copy-api-credential"
                type="button"
                phx-hook=".CopyCredential"
                data-copy-value={"#{@credential.client_id}.#{@credential.client_secret}"}
                class="mt-4 inline-flex items-center gap-2 rounded-lg bg-amber-950 px-3 py-2 text-sm font-semibold text-white transition hover:bg-slate-950"
              >
                <.icon name="hero-clipboard" class="size-4" /> Copy bearer credential
              </button>
              <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyCredential">
                export default {
                  mounted() {
                    this.el.addEventListener("click", () => navigator.clipboard.writeText(this.el.dataset.copyValue))
                  }
                }
              </script>
            </div>
          </div>
        </div>

        <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <div class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
            <div class="mb-5">
              <h2 class="text-lg font-semibold text-slate-950">API credentials</h2>
              <p class="mt-1 text-sm text-slate-600">
                Rotate safely by creating a replacement before revoking the old token.
              </p>
            </div>

            <div id="agent-tokens" phx-update="stream" class="space-y-3">
              <div
                id="agent-tokens-empty"
                class="hidden only:block rounded-xl border border-dashed border-slate-300 p-6 text-center text-sm text-slate-500"
              >
                No credentials have been issued.
              </div>
              <article
                :for={{id, token} <- @streams.tokens}
                id={id}
                class="rounded-xl border border-slate-200 p-4"
              >
                <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                  <div class="min-w-0">
                    <div class="flex flex-wrap items-center gap-2">
                      <h3 class="font-medium text-slate-950">{token.label}</h3>
                      <span
                        :if={token.revoked_at}
                        class="rounded-full bg-rose-50 px-2 py-0.5 text-xs font-medium text-rose-700"
                      >revoked</span>
                    </div>
                    <p class="mt-1 truncate font-mono text-xs text-slate-500">{token.id}</p>
                    <p class="mt-3 text-xs text-slate-500">
                      Expires {Calendar.strftime(token.expires_at, "%Y-%m-%d %H:%M UTC")}
                      <span :if={token.authenticated_at}> · Last used {Calendar.strftime(
                        token.authenticated_at,
                        "%Y-%m-%d %H:%M UTC"
                      )}</span>
                    </p>
                  </div>
                  <button
                    :if={is_nil(token.revoked_at)}
                    id={"revoke-token-#{token.id}"}
                    type="button"
                    phx-click="revoke"
                    phx-value-token_id={token.id}
                    data-confirm="Revoke this credential?"
                    class="text-sm font-semibold text-rose-700 transition hover:text-rose-900"
                  >
                    Revoke
                  </button>
                </div>
              </article>
            </div>
          </div>

          <aside class="h-fit rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
            <h2 class="font-semibold text-slate-950">Issue a credential</h2>
            <p class="mt-1 text-sm leading-6 text-slate-600">
              Secrets use 256 bits of randomness and are stored only as SHA-256 digests.
            </p>
            <.form for={@token_form} id="token-form" phx-submit="create_token" class="mt-5 space-y-4">
              <.input
                field={@token_form[:label]}
                type="text"
                label="Label"
                placeholder="production"
                required
                disabled={@agent.current_state != "active"}
                class="w-full rounded-xl border border-slate-300 bg-white px-3 py-2.5 text-slate-950 outline-none transition placeholder:text-slate-400 focus:border-sky-500 focus:ring-4 focus:ring-sky-100 disabled:bg-slate-100"
              />
              <.input
                field={@token_form[:expires_in_days]}
                type="select"
                label="Expires in"
                options={[{"30 days", "30"}, {"90 days", "90"}, {"1 year", "365"}]}
                disabled={@agent.current_state != "active"}
                class="w-full rounded-xl border border-slate-300 bg-white px-3 py-2.5 text-slate-950 outline-none transition focus:border-sky-500 focus:ring-4 focus:ring-sky-100 disabled:bg-slate-100"
              />
              <button
                id="create-token-button"
                type="submit"
                disabled={@agent.current_state != "active"}
                phx-disable-with="Generating…"
                class="inline-flex w-full items-center justify-center rounded-xl bg-slate-950 px-4 py-3 text-sm font-semibold text-white transition hover:bg-sky-950 disabled:cursor-not-allowed disabled:bg-slate-300"
              >
                Generate secret
              </button>
            </.form>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("create_token", %{"token" => params}, socket) do
    with {:ok, attrs} <- api_token_attrs(params),
         {:ok, %{credential: credential, token: token}} <-
           Accounts.create_agent_api_token(
             socket.assigns.current_scope.actor,
             socket.assigns.agent.id,
             attrs
           ) do
      {:noreply,
       socket
       |> assign(:credential, credential)
       |> assign(:token_form, token_form())
       |> stream_insert(:tokens, token, at: 0)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Credential could not be created.")}
    end
  end

  def handle_event("revoke", %{"token_id" => token_id}, socket) do
    owner = socket.assigns.current_scope.actor
    agent = socket.assigns.agent

    case Accounts.revoke_agent_api_token(owner, agent.id, token_id) do
      {:ok, token} ->
        {:noreply,
         socket
         |> put_flash(:info, "Credential revoked.")
         |> stream_insert(:tokens, token)}

      _ ->
        {:noreply, put_flash(socket, :error, "Credential could not be revoked.")}
    end
  end

  def handle_event("deactivate", _params, socket) do
    transition_agent(socket, :deactivate)
  end

  def handle_event("activate", _params, socket) do
    transition_agent(socket, :activate)
  end

  defp transition_agent(socket, transition) do
    agent = socket.assigns.agent
    owner = socket.assigns.current_scope.actor
    result = Agent.transition(owner, agent.id, transition)

    case result do
      {:ok, %{resource: updated_agent}} -> {:noreply, assign(socket, :agent, updated_agent)}
      _ -> {:noreply, put_flash(socket, :error, "Agent state could not be changed.")}
    end
  end

  defp api_token_attrs(%{"label" => label, "expires_in_days" => days})
       when days in @expiry_days do
    label = String.trim(label)

    if label == "" do
      {:error, :invalid_label}
    else
      {:ok,
       %{
         "label" => label,
         "expires_at" =>
           DateTime.utc_now(:microsecond)
           |> DateTime.add(String.to_integer(days), :day)
       }}
    end
  end

  defp api_token_attrs(_params), do: {:error, :invalid_expiry}

  defp token_form do
    to_form(%{"label" => "", "expires_in_days" => "90"}, as: :token)
  end
end
