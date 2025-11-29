defmodule JidoHub.RepoTest do
  use JidoHub.DataCase

  alias JidoHub.Repo

  describe "prefer_transaction?/0" do
    test "returns false" do
      assert Repo.prefer_transaction?() == false
    end
  end

  describe "installed_extensions/0" do
    test "returns expected extensions" do
      extensions = Repo.installed_extensions()
      expected = MapSet.new(["ash-functions", "citext"])
      assert MapSet.new(extensions) == expected
    end
  end

  describe "min_pg_version/0" do
    test "returns version 14.17.0" do
      assert %Version{major: 14, minor: 17, patch: 0} = Repo.min_pg_version()
    end
  end
end
