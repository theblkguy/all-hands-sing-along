defmodule AllHandsSingAlongWeb.PageController do
  use AllHandsSingAlongWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
