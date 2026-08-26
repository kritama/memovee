defmodule MemoveeWeb.Tama.Memory.PostJSON do
  @moduledoc """
  Renders canonical memory posts.
  """

  alias Memovee.Memory.Post

  def show(%{post: %Post{} = post}) do
    %{data: data(post)}
  end

  defp data(%Post{} = post) do
    %{
      id: post.id,
      title: post.title,
      body: post.body,
      body_hash: post.body_hash,
      metadata: post.metadata,
      inserted_at: post.inserted_at,
      updated_at: post.updated_at
    }
  end
end
