defmodule JidoHubWeb.PageControllerTest do
  use JidoHubWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "JidoHub"
  end
end
