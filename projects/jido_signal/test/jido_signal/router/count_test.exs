defmodule Jido.Signal.Router.CountTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Router
  alias Jido.Signal.Router.Engine

  describe "route_count tracking" do
    test "counts single-target routes correctly" do
      {:ok, router} =
        Router.new([
          {"user.created", :handler1},
          {"user.updated", :handler2},
          {"order.placed", :handler3}
        ])

      assert router.route_count == 3
    end

    test "counts multi-target routes correctly" do
      {:ok, router} =
        Router.new([
          {"system.error", [{:logger, []}, {:metrics, []}, {:alert, []}]}
        ])

      # Multi-target counts as 3 separate targets
      assert router.route_count == 3
    end

    test "maintains count after removal" do
      {:ok, router} =
        Router.new([
          {"user.created", :handler1},
          {"user.updated", :handler2},
          {"order.placed", :handler3}
        ])

      {:ok, router} = Router.remove(router, "user.created")
      assert router.route_count == 2

      {:ok, router} = Router.remove(router, ["user.updated", "order.placed"])
      assert router.route_count == 0
    end

    test "handles removal of non-existent path" do
      {:ok, router} = Router.new({"user.created", :handler1})

      {:ok, router} = Router.remove(router, "nonexistent.path")
      assert router.route_count == 1
    end

    test "route_count matches actual trie count (invariant)" do
      routes = [
        {"user.created", :h1},
        {"user.updated", :h2},
        {"order.**", :h3},
        {"system.error", [{:logger, []}, {:metrics, []}]}
      ]

      {:ok, router} = Router.new(routes)

      # Verify invariant
      actual_count = Engine.count_routes(router.trie)
      assert router.route_count == actual_count

      # After removal, invariant still holds
      {:ok, router} = Router.remove(router, "user.created")
      actual_count = Engine.count_routes(router.trie)
      assert router.route_count == actual_count
    end

    test "invariant holds after adding routes" do
      {:ok, router} = Router.new({"user.created", :handler1})

      {:ok, router} =
        Router.add(router, [
          {"user.updated", :handler2},
          {"system.error", [{:logger, []}, {:metrics, []}]}
        ])

      actual_count = Engine.count_routes(router.trie)
      assert router.route_count == actual_count
    end

    test "invariant holds with pattern matching routes" do
      match_fn = fn signal -> signal.data[:amount] > 1000 end

      {:ok, router} =
        Router.new([
          {"payment.processed", match_fn, :handler1},
          {"user.created", :handler2}
        ])

      actual_count = Engine.count_routes(router.trie)
      assert router.route_count == actual_count

      {:ok, router} = Router.remove(router, "payment.processed")
      actual_count = Engine.count_routes(router.trie)
      assert router.route_count == actual_count
    end

    test "invariant holds with wildcard routes" do
      {:ok, router} =
        Router.new([
          {"user.*", :handler1},
          {"user.**.created", :handler2},
          {"order.placed", :handler3}
        ])

      actual_count = Engine.count_routes(router.trie)
      assert router.route_count == actual_count

      {:ok, router} = Router.remove(router, "user.*")
      actual_count = Engine.count_routes(router.trie)
      assert router.route_count == actual_count
    end

    test "count doesn't go negative on repeated removal" do
      {:ok, router} = Router.new({"user.created", :handler1})

      {:ok, router} = Router.remove(router, "user.created")
      assert router.route_count == 0

      # Remove again - shouldn't go negative
      {:ok, router} = Router.remove(router, "user.created")
      assert router.route_count == 0
    end

    test "mixed operations maintain invariant" do
      {:ok, router} = Router.new({"user.created", :handler1})

      {:ok, router} = Router.add(router, {"user.updated", :handler2})
      assert router.route_count == Engine.count_routes(router.trie)

      {:ok, router} = Router.add(router, {"system.error", [{:logger, []}, {:alert, []}]})
      assert router.route_count == Engine.count_routes(router.trie)

      {:ok, router} = Router.remove(router, "user.created")
      assert router.route_count == Engine.count_routes(router.trie)

      {:ok, router} = Router.remove(router, ["user.updated", "system.error"])
      assert router.route_count == Engine.count_routes(router.trie)
    end
  end
end
