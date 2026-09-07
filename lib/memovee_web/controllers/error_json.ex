defmodule MemoveeWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  def render("memory.json", %{code: code, message: message}) do
    %{error: %{code: code, message: message, retryable: false, details: %{}}}
  end

  def render(template, _assigns) do
    message = Phoenix.Controller.status_message_from_template(template)

    %{
      errors: [
        %{
          status: status_from_template(template),
          title: message,
          detail: message
        }
      ]
    }
  end

  defp status_from_template(template) do
    template
    |> to_string()
    |> String.trim_trailing(".json")
  end
end
