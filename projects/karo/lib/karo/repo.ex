defmodule Karo.Repo do
  @moduledoc """
  Ash SQLite repository for Karo persistence.
  """

  use AshSqlite.Repo, otp_app: :karo
end
