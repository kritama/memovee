defmodule Memovee.Projections do
  @moduledoc """
  The Projections context.
  """

  alias __MODULE__.Indexing

  defdelegate create_indexing(scope, post), to: Indexing.Manager, as: :create
  defdelegate get_post_indexing(scope, post), to: Indexing.Manager, as: :get_for_post
  defdelegate bump_indexing_revision(scope, post), to: Indexing.Manager, as: :bump
end
