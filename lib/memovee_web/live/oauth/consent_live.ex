defmodule MemoveeWeb.OAuth.ConsentLive do
  @moduledoc false

  use MemoveeWeb, :live_view

  alias Memovee.OAuth

  @impl true
  def mount(%{"handle" => handle}, _session, socket) do
    case OAuth.consent(socket.assigns.current_scope, handle) do
      {:ok, consent} ->
        {:ok,
         socket
         |> assign(:page_title, "Authorize application")
         |> assign(:handle, handle)
         |> assign(:consent, consent)
         |> assign(:invalid?, false)
         |> assign(:form, to_form(%{}, as: :consent))}

      {:error, _reason} ->
        {:ok,
         socket
         |> assign(:page_title, "Invalid authorization request")
         |> assign(:handle, handle)
         |> assign(:consent, nil)
         |> assign(:invalid?, true)
         |> assign(:form, to_form(%{}, as: :consent))}
    end
  end

  @impl true
  def handle_event("decide", %{"consent" => %{"decision" => decision}}, socket)
      when decision in ["approve", "deny"] do
    result =
      case decision do
        "approve" -> OAuth.approve(socket.assigns.current_scope, socket.assigns.handle)
        "deny" -> OAuth.deny(socket.assigns.current_scope, socket.assigns.handle)
      end

    case result do
      {:ok, redirect_uri} -> {:noreply, redirect(socket, external: redirect_uri)}
      {:error, _reason} -> {:noreply, assign(socket, :invalid?, true)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="oauth-consent" class={["mx-auto flex min-h-[70vh] max-w-2xl items-center px-4 py-12"]}>
        <section class={["card w-full border border-base-300 bg-base-100 shadow-xl"]}>
          <div class={["card-body gap-6"]}>
            <div>
              <p class={["text-primary text-sm font-semibold tracking-wide uppercase"]}>
                OAuth access
              </p>
              <h1 class={["card-title mt-2 text-3xl"]}>Authorize Tama</h1>
              <p class={["mt-2 text-base-content/65"]}>
                Review the application and permission before continuing.
              </p>
            </div>

            <div :if={@invalid?} id="oauth-consent-error" class={["alert alert-error"]}>
              <.icon name="hero-exclamation-circle" class={["size-5"]} />
              <span>This authorization request is invalid or has expired.</span>
            </div>

            <div :if={!@invalid?} class={["space-y-6"]}>
              <dl class={["grid gap-4 rounded-box bg-base-200 p-5 sm:grid-cols-3"]}>
                <dt class={["font-medium"]}>Application</dt>
                <dd id="oauth-consent-client-name" class={["break-words sm:col-span-2"]}>
                  {@consent.client_name}
                </dd>

                <dt class={["font-medium"]}>Callback</dt>
                <dd id="oauth-consent-redirect-authority" class={["break-all sm:col-span-2"]}>
                  {@consent.redirect_authority}
                </dd>

                <dt class={["font-medium"]}>Resource</dt>
                <dd id="oauth-consent-resource" class={["break-all sm:col-span-2"]}>
                  {@consent.request.resource}
                </dd>

                <dt class={["font-medium"]}>Permission</dt>
                <dd id="oauth-consent-scopes" class={["sm:col-span-2"]}>
                  <span class={["badge badge-primary badge-outline"]}>Send messages as you</span>
                </dd>
              </dl>

              <div class={["alert alert-warning"]}>
                <.icon name="hero-shield-check" class={["size-5"]} />
                <span>Tama will receive your stable Memovee Actor ID, not your email address.</span>
              </div>

              <.form for={@form} id="oauth-consent-form" phx-submit="decide" class={["flex gap-3"]}>
                <button
                  id="oauth-consent-deny"
                  class={["btn btn-ghost flex-1 transition-transform hover:-translate-y-0.5"]}
                  name="consent[decision]"
                  value="deny"
                >
                  Deny
                </button>
                <button
                  id="oauth-consent-approve"
                  class={["btn btn-primary flex-1 transition-transform hover:-translate-y-0.5"]}
                  name="consent[decision]"
                  value="approve"
                >
                  Authorize
                </button>
              </.form>
            </div>
          </div>
        </section>
      </main>
    </Layouts.app>
    """
  end
end
