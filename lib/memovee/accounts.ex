defmodule Memovee.Accounts do
  @moduledoc """
  The Accounts context. Actors are the stable application principals; Users
  and Tokens are authentication records attached to them.
  """

  alias __MODULE__.{Actor, Token, User}

  defdelegate transition_actor(actor, transitioning_actor, event),
    to: Actor.Manager,
    as: :transition

  defdelegate get_user_by_email(email), to: User.Manager, as: :get_by_email

  defdelegate get_user_by_email_and_password(email, password),
    to: User.Manager,
    as: :get_by_email_and_password

  defdelegate get_user!(id), to: User.Manager, as: :get!
  defdelegate register_user(attrs), to: User.Manager, as: :register
  defdelegate sudo_mode?(user, minutes \\ -10), to: User.Manager

  defdelegate change_user_email(user, attrs \\ %{}, opts \\ []),
    to: User.Manager,
    as: :change_email

  defdelegate update_user_email(user, token), to: User.Manager, as: :update_email

  defdelegate change_user_password(user, attrs \\ %{}, opts \\ []),
    to: User.Manager,
    as: :change_password

  defdelegate update_user_password(user, attrs), to: User.Manager, as: :update_password
  defdelegate get_user_by_magic_link_token(token), to: User.Manager, as: :get_by_magic_link_token
  defdelegate login_user_by_magic_link(token), to: User.Manager, as: :login_by_magic_link

  defdelegate deliver_user_update_email_instructions(user, current_email, url_fun),
    to: User.Manager,
    as: :deliver_update_email_instructions

  defdelegate deliver_login_instructions(user, url_fun), to: User.Manager

  defdelegate generate_user_session_token(user), to: Token.Manager, as: :generate_session_token
  defdelegate get_user_by_session_token(token), to: Token.Manager
  defdelegate delete_user_session_token(token), to: Token.Manager, as: :delete_session_token

  defdelegate create_agent_api_token(owner, agent_id, attrs),
    to: Token.Manager,
    as: :create_api_token

  defdelegate get_agent_with_api_tokens(owner, agent_id), to: Token.Manager

  defdelegate revoke_agent_api_token(owner, agent_id, token_id),
    to: Token.Manager,
    as: :revoke_api_token

  defdelegate verify_api_token(client_id, client_secret), to: Token.Manager
end
