defmodule Memovee.Memory do
  @moduledoc """
  The Memory context.
  """

  alias __MODULE__.{Post, Projection, Tag, Tagging}

  defdelegate list_posts(), to: Post.Manager, as: :list
  defdelegate get_post!(id), to: Post.Manager, as: :get!
  defdelegate create_post(attrs), to: Post.Manager, as: :create
  defdelegate update_post(actor, post, attrs), to: Post.Manager, as: :update
  defdelegate change_post(post, attrs \\ %{}), to: Post.Manager, as: :change

  defdelegate list_tags(), to: Tag.Manager, as: :list
  defdelegate get_tag!(id), to: Tag.Manager, as: :get!

  defdelegate get_tag_by_namespace_and_key(namespace, key),
    to: Tag.Manager,
    as: :get_by_namespace_and_key

  defdelegate create_tag(attrs), to: Tag.Manager, as: :create
  defdelegate update_tag(tag, attrs), to: Tag.Manager, as: :update
  defdelegate change_tag(tag, attrs \\ %{}), to: Tag.Manager, as: :change
  defdelegate list_post_tags(post), to: Tag.Manager, as: :list_for_post

  defdelegate tag_post(post, tag), to: Tagging.Manager, as: :create
  defdelegate untag_post(post, tag), to: Tagging.Manager, as: :delete

  defdelegate list_post_projections(post), to: Projection.Manager, as: :list_for_post
  defdelegate list_pending_projections(), to: Projection.Manager, as: :list_pending
  defdelegate get_projection!(id), to: Projection.Manager, as: :get!
  defdelegate create_projection(post, attrs), to: Projection.Manager, as: :create
  defdelegate change_projection(projection, attrs \\ %{}), to: Projection.Manager, as: :change
  defdelegate start_projection_sync(actor, projection), to: Projection.Manager, as: :sync

  defdelegate complete_projection_sync(actor, projection, tama_entity_id, body_hash),
    to: Projection.Manager,
    as: :complete

  defdelegate fail_projection_sync(actor, projection, reason), to: Projection.Manager, as: :fail
  defdelegate retry_projection_sync(actor, projection), to: Projection.Manager, as: :retry
  defdelegate invalidate_projection(actor, projection), to: Projection.Manager, as: :invalidate
end
