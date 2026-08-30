defmodule MemoveeWeb.ChangesetJSON do
  @moduledoc """
  Renders Ecto changeset errors in the JSON:API validation error shape.

  Errors from nested changesets are flattened into the JSON:API error list
  with their full source pointer.
  """

  def error(%{changeset: changeset}) do
    %{errors: render_changeset_errors(changeset, [])}
  end

  defp render_changeset_errors(changeset, path) do
    direct_errors = Enum.flat_map(changeset.errors, &render_error(&1, path))

    nested_errors =
      changeset.changes
      |> Enum.flat_map(&render_nested_errors(&1, path))

    direct_errors ++ nested_errors
  end

  defp render_error({field, {message, options}}, path) do
    error = %{
      title: "Invalid value",
      source: %{pointer: json_pointer(path ++ [field])},
      detail: interpolate_error_message(message, options)
    }

    case find_embedded_changeset(options) do
      %Ecto.Changeset{} = changeset ->
        [error | render_changeset_errors(changeset, path ++ [field])]

      nil ->
        [error]
    end
  end

  defp render_nested_errors({key, %Ecto.Changeset{valid?: false} = changeset}, path) do
    render_changeset_errors(changeset, path ++ [key])
  end

  defp render_nested_errors({key, changesets}, path) when is_list(changesets) do
    changesets
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {%Ecto.Changeset{valid?: false} = changeset, index} ->
        render_changeset_errors(changeset, path ++ [key, index])

      {_changeset, _index} ->
        []
    end)
  end

  defp render_nested_errors(_change, _path), do: []

  defp interpolate_error_message(message, options) do
    Enum.reduce(options, message, fn {key, value}, translated ->
      String.replace(translated, "%{#{key}}", fn _match -> to_string(value) end)
    end)
  end

  defp json_pointer(path) do
    "/" <> Enum.map_join(path, "/", &escape_pointer_segment/1)
  end

  defp find_embedded_changeset(options) do
    Enum.find_value(options, fn
      {_key, %Ecto.Changeset{} = changeset} -> changeset
      _option -> nil
    end)
  end

  defp escape_pointer_segment(segment) do
    segment
    |> to_string()
    |> String.replace("~", "~0")
    |> String.replace("/", "~1")
  end
end
