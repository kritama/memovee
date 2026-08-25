defmodule Memovee.Memory.Tagging.Manager do
  @moduledoc """
  Maintains tag assignments for memory posts.
  """

  import Ecto.Query, only: [where: 3]

  alias Memovee.Memory.{Post, Tag, Tagging}
  alias Memovee.Repo

  def create(%Post{} = post, %Tag{} = tag) do
    %Tagging{}
    |> Tagging.changeset(post, tag)
    |> Repo.insert()
  end

  def delete(%Post{} = post, %Tag{} = tag) do
    Tagging
    |> where([tagging], tagging.post_id == ^post.id and tagging.tag_id == ^tag.id)
    |> Repo.delete_all()
  end
end
