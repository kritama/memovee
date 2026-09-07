defmodule Memovee.Projections do
  @moduledoc """
  The Projections context.
  """

  alias __MODULE__.Indexing

  defdelegate create_indexing(post), to: Indexing.Manager, as: :create
  defdelegate get_post_indexing!(post), to: Indexing.Manager, as: :get_for_post!
  defdelegate bump_indexing_revision(post), to: Indexing.Manager, as: :bump
end
