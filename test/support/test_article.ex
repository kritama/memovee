defmodule Memovee.TestArticle do
  @moduledoc false

  use Memovee.Schema

  schema "test_articles" do
    field :title, :string
    belongs_to :parent, __MODULE__
    timestamps()
  end

  @doc false
  def changeset(article, attrs) do
    article
    |> cast(attrs, [:title, :parent_id])
    |> validate_required([:title])
  end
end
