defmodule MemoveeWeb.UserLive.SettingsTest do
  use MemoveeWeb.ConnCase, async: false

  alias Memovee.Accounts
  alias Memovee.Accounts.Scope
  alias MemoveeWeb.UserLive.Settings
  alias Phoenix.LiveView
  import Phoenix.LiveViewTest
  import Memovee.AccountsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Change Email"
      assert html =~ "Save Password"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "redirects if user is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/users/settings")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert conn.resp_body =~ "You must re-authenticate to access this page."
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Accounts.get_user_by_email(user.email)
    end

    test "shows an error when the confirmation email cannot be delivered", %{conn: conn} do
      mailer_config = Application.fetch_env!(:memovee, Memovee.Mailer)

      Application.put_env(
        :memovee,
        Memovee.Mailer,
        Keyword.put(mailer_config, :adapter, Memovee.Test.FailingMailerAdapter)
      )

      on_exit(fn -> Application.put_env(:memovee, Memovee.Mailer, mailer_config) end)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => unique_user_email()}
        })
        |> render_submit()

      assert result =~ "The confirmation email could not be sent. Please try again."
      refute result =~ "A link to confirm your email change has been sent"
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
    end

    test "redirects to reauthentication when sudo mode expires before submission", %{user: user} do
      {:noreply, socket} =
        Settings.handle_event(
          "update_email",
          %{"user" => %{"email" => unique_user_email()}},
          expired_settings_socket(user)
        )

      assert {:live, :redirect, %{to: "/users/log-in", kind: :push}} = socket.redirected

      assert Phoenix.Flash.get(socket.assigns.flash, :error) ==
               "You must re-authenticate to access this page."
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user password", %{conn: conn, user: user} do
      new_password = valid_user_password()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      form =
        form(lv, "#password_form", %{
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/users/settings"

      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#password_form", %{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "redirects to reauthentication when sudo mode expires before submission", %{user: user} do
      {:noreply, socket} =
        Settings.handle_event(
          "update_password",
          %{
            "user" => %{
              "password" => valid_user_password(),
              "password_confirmation" => valid_user_password()
            }
          },
          expired_settings_socket(user)
        )

      assert {:live, :redirect, %{to: "/users/log-in", kind: :push}} = socket.redirected
      refute Map.get(socket.assigns, :trigger_submit)

      assert Phoenix.Flash.get(socket.assigns.flash, :error) ==
               "You must re-authenticate to access this page."
    end
  end

  defp expired_settings_socket(user) do
    expired_user =
      %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)}

    %LiveView.Socket{
      endpoint: MemoveeWeb.Endpoint,
      router: MemoveeWeb.Router,
      assigns: %{
        __changed__: %{},
        flash: %{},
        current_scope: Scope.for_user(expired_user)
      }
    }
  end
end
