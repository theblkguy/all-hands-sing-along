defmodule AllHandsSingAlongWeb.ErrorJSONTest do
  use AllHandsSingAlongWeb.ConnCase

  test "renders 404" do
    assert AllHandsSingAlongWeb.ErrorJSON.render("404.json", %{}) == %{
             errors: %{detail: "Not Found"}
           }
  end

  test "renders 500" do
    assert AllHandsSingAlongWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
