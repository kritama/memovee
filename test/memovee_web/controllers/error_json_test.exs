defmodule MemoveeWeb.ErrorJSONTest do
  use MemoveeWeb.ConnCase, async: true

  test "renders 404" do
    assert MemoveeWeb.ErrorJSON.render("404.json", %{}) == %{
             errors: [
               %{
                 status: "404",
                 title: "Not Found",
                 detail: "Not Found"
               }
             ]
           }
  end

  test "renders 500" do
    assert MemoveeWeb.ErrorJSON.render("500.json", %{}) ==
             %{
               errors: [
                 %{
                   status: "500",
                   title: "Internal Server Error",
                   detail: "Internal Server Error"
                 }
               ]
             }
  end
end
