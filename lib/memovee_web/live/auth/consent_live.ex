defmodule MemoveeWeb.Auth.ConsentLive do
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

                <dt class={["font-medium"]}>Verification</dt>
                <dd id="oauth-consent-client-verification" class={["sm:col-span-2"]}>
                  <span class={[
                    "badge badge-outline",
                    if(@consent.verified_client_metadata?,
                      do: "badge-success",
                      else: "badge-warning"
                    )
                  ]}>
                    {if(@consent.verified_client_metadata?,
                      do: "Verified metadata",
                      else: "Unverified metadata"
                    )}
                  </span>
                </dd>

                <dt :if={@consent.client_uri} class={["font-medium"]}>Website</dt>
                <dd
                  :if={@consent.client_uri}
                  id="oauth-consent-client-uri"
                  class={["break-all sm:col-span-2"]}
                >
                  <.link
                    href={@consent.client_uri}
                    target="_blank"
                    rel="noreferrer"
                    class={["link link-primary"]}
                  >
                    {@consent.client_uri}
                  </.link>
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
                  Send messages to Tama for processing on your behalf.
                </dd>
              </dl>

              <div
                :if={!@consent.verified_client_metadata? || @consent.loopback_redirect?}
                id="oauth-consent-client-warning"
                class={["alert alert-warning items-start"]}
              >
                <.icon name="hero-exclamation-triangle" class={["mt-0.5 size-5 shrink-0"]} />
                <div class={["space-y-1"]}>
                  <p :if={!@consent.verified_client_metadata?} id="oauth-consent-unverified-warning">
                    Memovee could not independently verify this application's metadata. Only
                    continue if you initiated this request and recognize the application.
                  </p>
                  <p :if={@consent.loopback_redirect?} id="oauth-consent-loopback-warning">
                    This application will receive the authorization result on this device through a
                    local callback.
                  </p>
                </div>
              </div>

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
