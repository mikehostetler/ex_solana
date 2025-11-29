defmodule JidoHubWeb.PageController do
  use JidoHubWeb, :controller

  def home(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_layout(html: {JidoHubWeb.Layouts, :public})
        |> render(:home)

      _user ->
        redirect(conn, to: ~p"/dashboard")
    end
  end

  def index(conn, _params) do
    render(conn, :index)
  end

  def privacy(conn, _params) do
    conn
    |> put_layout(html: {JidoHubWeb.Layouts, :public})
    |> render(:privacy)
  end

  def terms(conn, _params) do
    conn
    |> put_layout(html: {JidoHubWeb.Layouts, :public})
    |> render(:terms)
  end
end
