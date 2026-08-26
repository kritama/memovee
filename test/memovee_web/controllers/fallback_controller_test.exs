defmodule MemoveeWeb.FallbackControllerTest do
  use MemoveeWeb.ConnCase, async: true

  alias Memovee.Memory.Post
  alias MemoveeWeb.FallbackController

  test "renders changeset errors in the JSON:API validation shape", %{conn: conn} do
    changeset = Post.changeset(%Post{}, %{"body" => " \n\t "})

    conn =
      conn
      |> Phoenix.Controller.put_format(:json)
      |> FallbackController.call({:error, changeset})

    assert json_response(conn, 422) == %{
             "errors" => [
               %{
                 "title" => "Invalid value",
                 "source" => %{"pointer" => "/body"},
                 "detail" => "can't be blank"
               }
             ]
           }
  end

  test "renders errors from nested changesets", %{conn: conn} do
    nested_changeset =
      {%{}, %{data: :string}}
      |> Ecto.Changeset.cast(%{}, [:data])
      |> Ecto.Changeset.validate_required([:data])

    changeset = %Ecto.Changeset{
      changes: %{configuration: nested_changeset},
      errors: [],
      valid?: false
    }

    conn =
      conn
      |> Phoenix.Controller.put_format(:json)
      |> FallbackController.call({:error, changeset})

    assert json_response(conn, 422) == %{
             "errors" => [
               %{
                 "title" => "Invalid value",
                 "source" => %{"pointer" => "/configuration/data"},
                 "detail" => "can't be blank"
               }
             ]
           }
  end

  test "includes indexes in pointers for nested changeset lists", %{conn: conn} do
    valid_changeset =
      {%{}, %{data: :string}}
      |> Ecto.Changeset.cast(%{"data" => "present"}, [:data])
      |> Ecto.Changeset.validate_required([:data])

    invalid_changeset =
      {%{}, %{data: :string}}
      |> Ecto.Changeset.cast(%{}, [:data])
      |> Ecto.Changeset.validate_required([:data])

    configuration_changeset = %Ecto.Changeset{
      changes: %{series: [valid_changeset, invalid_changeset]},
      errors: [],
      valid?: false
    }

    changeset = %Ecto.Changeset{
      changes: %{configuration: configuration_changeset},
      errors: [],
      valid?: false
    }

    conn =
      conn
      |> Phoenix.Controller.put_format(:json)
      |> FallbackController.call({:error, changeset})

    assert json_response(conn, 422) == %{
             "errors" => [
               %{
                 "title" => "Invalid value",
                 "source" => %{"pointer" => "/configuration/series/1/data"},
                 "detail" => "can't be blank"
               }
             ]
           }
  end

  test "renders nested changesets carried by an error", %{conn: conn} do
    nested_changeset =
      {%{}, %{data: :string}}
      |> Ecto.Changeset.cast(%{}, [:data])
      |> Ecto.Changeset.validate_required([:data])

    changeset = %Ecto.Changeset{
      changes: %{},
      errors: [configuration: {"is invalid", [changeset: nested_changeset]}],
      valid?: false
    }

    conn =
      conn
      |> Phoenix.Controller.put_format(:json)
      |> FallbackController.call({:error, changeset})

    assert json_response(conn, 422) == %{
             "errors" => [
               %{
                 "title" => "Invalid value",
                 "source" => %{"pointer" => "/configuration"},
                 "detail" => "is invalid"
               },
               %{
                 "title" => "Invalid value",
                 "source" => %{"pointer" => "/configuration/data"},
                 "detail" => "can't be blank"
               }
             ]
           }
  end

  test "renders common action errors", %{conn: conn} do
    not_found_conn =
      conn
      |> Phoenix.Controller.put_format(:json)
      |> FallbackController.call({:error, :not_found})

    assert json_response(not_found_conn, 404) == %{
             "errors" => [
               %{
                 "status" => "404",
                 "title" => "Not Found",
                 "detail" => "Not Found"
               }
             ]
           }

    unauthorized_conn =
      build_conn()
      |> Phoenix.Controller.put_format(:json)
      |> FallbackController.call({:error, :unauthorized})

    assert json_response(unauthorized_conn, 401) == %{
             "errors" => [
               %{
                 "status" => "401",
                 "title" => "Unauthorized",
                 "detail" => "Unauthorized"
               }
             ]
           }
  end
end
