defmodule JidoHubWeb.HomePagePlaywrightTest do
  use PhoenixTest.Playwright.Case, async: false

  @moduletag :playwright

  test "visiting the home page", %{conn: conn} do
    conn
    |> visit("/")
    |> assert_has("h1")
  end
end
