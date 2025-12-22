defmodule JidoCode.TUI.Widgets.SessionSidebarTest do
  use ExUnit.Case, async: true

  alias JidoCode.TUI.Widgets.SessionSidebar
  alias JidoCode.Session

  # Test helper to create a session
  defp create_session(opts \\ []) do
    %Session{
      id: Keyword.get(opts, :id, "session_#{:rand.uniform(10000)}"),
      name: Keyword.get(opts, :name, "Test Session"),
      project_path: Keyword.get(opts, :project_path, "/home/user/project"),
      config: %{provider: "anthropic", model: "claude-3-5-sonnet-20241022"},
      created_at: Keyword.get(opts, :created_at, DateTime.utc_now()),
      updated_at: DateTime.utc_now()
    }
  end

  # ============================================================================
  # Constructor Tests
  # ============================================================================

  describe "new/1" do
    test "creates empty sidebar with default values" do
      sidebar = SessionSidebar.new()

      assert sidebar.sessions == []
      assert sidebar.order == []
      assert sidebar.active_id == nil
      assert sidebar.expanded == MapSet.new()
      assert sidebar.width == 20
    end

    test "creates sidebar with sessions" do
      sessions = [create_session(id: "s1"), create_session(id: "s2")]
      order = ["s1", "s2"]

      sidebar = SessionSidebar.new(sessions: sessions, order: order)

      assert length(sidebar.sessions) == 2
      assert sidebar.order == ["s1", "s2"]
    end

    test "creates sidebar with active session" do
      session = create_session(id: "active_123")
      sidebar = SessionSidebar.new(sessions: [session], active_id: "active_123")

      assert sidebar.active_id == "active_123"
    end

    test "creates sidebar with expanded sessions" do
      sidebar = SessionSidebar.new(expanded: MapSet.new(["s1", "s2"]))

      assert MapSet.member?(sidebar.expanded, "s1")
      assert MapSet.member?(sidebar.expanded, "s2")
    end

    test "accepts custom width" do
      sidebar = SessionSidebar.new(width: 30)

      assert sidebar.width == 30
    end
  end

  # ============================================================================
  # Badge Calculation Tests
  # ============================================================================

  describe "build_badge/1" do
    test "returns badge with message count and status icon" do
      # Note: This will use live Session.State, which may return 0 messages
      # We're testing the format, not specific counts
      session_id = "test_session"
      badge = SessionSidebar.build_badge(session_id)

      # Badge format: "(msgs: N) [icon]"
      assert String.starts_with?(badge, "(msgs: ")
      assert String.contains?(badge, ")")

      # Should contain a status icon
      assert Regex.match?(~r/[✓⟳✗○]/, badge)
    end

    test "badge format matches expected pattern" do
      session_id = "test_session"
      badge = SessionSidebar.build_badge(session_id)

      # Regex: "(msgs: \d+) [status_icon]"
      assert Regex.match?(~r/\(msgs: \d+\) [✓⟳✗○]/, badge)
    end
  end

  # ============================================================================
  # Title Formatting Tests
  # ============================================================================

  describe "build_title/2" do
    test "adds active indicator for active session" do
      session = create_session(id: "active_123", name: "My Project")
      sidebar = SessionSidebar.new(active_id: "active_123")

      title = SessionSidebar.build_title(sidebar, session)

      assert String.starts_with?(title, "→ ")
      assert String.contains?(title, "My Project")
    end

    test "no prefix for inactive session" do
      session = create_session(id: "inactive_456", name: "Other Project")
      sidebar = SessionSidebar.new(active_id: "active_123")

      title = SessionSidebar.build_title(sidebar, session)

      refute String.starts_with?(title, "→")
      assert title == "Other Project"
    end

    test "truncates long session names to 15 chars" do
      session = create_session(id: "s1", name: "Very Long Session Name Here")
      sidebar = SessionSidebar.new()

      title = SessionSidebar.build_title(sidebar, session)

      assert String.length(title) == 15
      assert String.ends_with?(title, "…")
    end

    test "truncates long active session names including indicator" do
      session = create_session(id: "active_123", name: "Very Long Session Name")
      sidebar = SessionSidebar.new(active_id: "active_123")

      title = SessionSidebar.build_title(sidebar, session)

      # "→ " + truncated name (13 chars)
      assert String.starts_with?(title, "→ ")
      # Full title should be "→ " (2 chars) + name portion
      assert String.contains?(title, "…")
    end

    test "preserves short names unchanged" do
      session = create_session(id: "s1", name: "Short")
      sidebar = SessionSidebar.new()

      title = SessionSidebar.build_title(sidebar, session)

      assert title == "Short"
    end
  end

  # ============================================================================
  # Session Details Tests
  # ============================================================================

  describe "build_session_details/1" do
    test "returns list of TermUI elements" do
      session = create_session()
      details = SessionSidebar.build_session_details(session)

      assert is_list(details)
      assert length(details) > 0
    end

    test "includes Info section with created time" do
      session = create_session()
      details = SessionSidebar.build_session_details(session)

      # Convert details to strings for easier testing
      detail_strings = Enum.map(details, fn elem -> inspect(elem) end)
      combined = Enum.join(detail_strings, " ")

      assert String.contains?(combined, "Info")
      assert String.contains?(combined, "Created:")
    end

    test "includes project path in Info section" do
      session = create_session(project_path: "/home/user/myproject")
      details = SessionSidebar.build_session_details(session)

      detail_strings = Enum.map(details, fn elem -> inspect(elem) end)
      combined = Enum.join(detail_strings, " ")

      assert String.contains?(combined, "Path:")
    end

    test "includes Files section with empty placeholder" do
      session = create_session()
      details = SessionSidebar.build_session_details(session)

      detail_strings = Enum.map(details, fn elem -> inspect(elem) end)
      combined = Enum.join(detail_strings, " ")

      assert String.contains?(combined, "Files")
      assert String.contains?(combined, "(empty)")
    end

    test "includes Tools section with empty placeholder" do
      session = create_session()
      details = SessionSidebar.build_session_details(session)

      detail_strings = Enum.map(details, fn elem -> inspect(elem) end)
      combined = Enum.join(detail_strings, " ")

      assert String.contains?(combined, "Tools")
    end
  end

  # ============================================================================
  # Rendering Tests
  # ============================================================================

  describe "render/2" do
    test "renders empty sidebar with header" do
      sidebar = SessionSidebar.new()
      view = SessionSidebar.render(sidebar, 20)

      # Should return a TermUI view (not nil)
      assert view != nil
    end

    test "renders sidebar with single session" do
      session = create_session(id: "s1", name: "Project")
      sidebar = SessionSidebar.new(sessions: [session], order: ["s1"])

      view = SessionSidebar.render(sidebar, 20)

      assert view != nil
    end

    test "renders sidebar with multiple sessions" do
      sessions = [
        create_session(id: "s1", name: "Project 1"),
        create_session(id: "s2", name: "Project 2"),
        create_session(id: "s3", name: "Project 3")
      ]

      sidebar =
        SessionSidebar.new(
          sessions: sessions,
          order: ["s1", "s2", "s3"]
        )

      view = SessionSidebar.render(sidebar, 25)

      assert view != nil
    end

    test "renders with expanded sessions" do
      session = create_session(id: "s1", name: "Project")

      sidebar =
        SessionSidebar.new(
          sessions: [session],
          order: ["s1"],
          expanded: MapSet.new(["s1"])
        )

      view = SessionSidebar.render(sidebar, 20)

      assert view != nil
    end

    test "renders with active session" do
      session = create_session(id: "active_s1", name: "Active Project")

      sidebar =
        SessionSidebar.new(
          sessions: [session],
          order: ["active_s1"],
          active_id: "active_s1"
        )

      view = SessionSidebar.render(sidebar, 20)

      assert view != nil
    end

    test "uses sidebar width if width not specified" do
      session = create_session(id: "s1")
      sidebar = SessionSidebar.new(sessions: [session], order: ["s1"], width: 30)

      view = SessionSidebar.render(sidebar)

      assert view != nil
    end

    test "renders correctly when session in order not found in sessions list" do
      # Edge case: order references session that doesn't exist in sessions list
      session = create_session(id: "s1")
      sidebar = SessionSidebar.new(sessions: [session], order: ["s1", "missing_s2"])

      view = SessionSidebar.render(sidebar, 20)

      # Should render without error (skips missing session)
      assert view != nil
    end
  end

  # ============================================================================
  # Accessor Function Tests
  # ============================================================================

  describe "expanded?/2" do
    test "returns true for expanded session" do
      sidebar = SessionSidebar.new(expanded: MapSet.new(["s1"]))

      assert SessionSidebar.expanded?(sidebar, "s1")
    end

    test "returns false for collapsed session" do
      sidebar = SessionSidebar.new(expanded: MapSet.new(["s1"]))

      refute SessionSidebar.expanded?(sidebar, "s2")
    end

    test "returns false for non-existent session" do
      sidebar = SessionSidebar.new()

      refute SessionSidebar.expanded?(sidebar, "non_existent")
    end
  end

  describe "session_count/1" do
    test "returns 0 for empty sidebar" do
      sidebar = SessionSidebar.new()

      assert SessionSidebar.session_count(sidebar) == 0
    end

    test "returns correct count for sidebar with sessions" do
      sessions = [
        create_session(id: "s1"),
        create_session(id: "s2"),
        create_session(id: "s3")
      ]

      sidebar = SessionSidebar.new(sessions: sessions)

      assert SessionSidebar.session_count(sidebar) == 3
    end
  end

  describe "has_active_session?/1" do
    test "returns true when active session set" do
      sidebar = SessionSidebar.new(active_id: "session_123")

      assert SessionSidebar.has_active_session?(sidebar)
    end

    test "returns false when no active session" do
      sidebar = SessionSidebar.new()

      refute SessionSidebar.has_active_session?(sidebar)
    end
  end

  # ============================================================================
  # Path Formatting Tests
  # ============================================================================

  describe "format_project_path (via build_session_details)" do
    test "replaces home directory with ~" do
      home_dir = System.user_home!()
      path = Path.join(home_dir, "projects/myapp")
      session = create_session(project_path: path)

      details = SessionSidebar.build_session_details(session)
      detail_strings = Enum.map(details, fn elem -> inspect(elem) end)
      combined = Enum.join(detail_strings, " ")

      assert String.contains?(combined, "~/projects/myapp")
    end

    test "keeps non-home paths unchanged" do
      session = create_session(project_path: "/opt/myproject")
      details = SessionSidebar.build_session_details(session)

      detail_strings = Enum.map(details, fn elem -> inspect(elem) end)
      combined = Enum.join(detail_strings, " ")

      assert String.contains?(combined, "/opt/myproject")
    end
  end

  # ============================================================================
  # Time Formatting Tests
  # ============================================================================

  describe "format_created_time (via build_session_details)" do
    test "formats recent time in seconds" do
      created_at = DateTime.add(DateTime.utc_now(), -30, :second)
      session = create_session(created_at: created_at)

      details = SessionSidebar.build_session_details(session)
      detail_strings = Enum.map(details, fn elem -> inspect(elem) end)
      combined = Enum.join(detail_strings, " ")

      assert String.contains?(combined, "s ago")
    end

    test "formats time in minutes" do
      created_at = DateTime.add(DateTime.utc_now(), -5 * 60, :second)
      session = create_session(created_at: created_at)

      details = SessionSidebar.build_session_details(session)
      detail_strings = Enum.map(details, fn elem -> inspect(elem) end)
      combined = Enum.join(detail_strings, " ")

      assert String.contains?(combined, "m ago")
    end

    test "formats time in hours" do
      created_at = DateTime.add(DateTime.utc_now(), -2 * 3600, :second)
      session = create_session(created_at: created_at)

      details = SessionSidebar.build_session_details(session)
      detail_strings = Enum.map(details, fn elem -> inspect(elem) end)
      combined = Enum.join(detail_strings, " ")

      assert String.contains?(combined, "h ago")
    end

    test "formats time in days" do
      created_at = DateTime.add(DateTime.utc_now(), -3 * 86400, :second)
      session = create_session(created_at: created_at)

      details = SessionSidebar.build_session_details(session)
      detail_strings = Enum.map(details, fn elem -> inspect(elem) end)
      combined = Enum.join(detail_strings, " ")

      assert String.contains?(combined, "d ago")
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "integration scenarios" do
    test "full workflow: create sidebar, render with multiple sessions" do
      sessions = [
        create_session(id: "s1", name: "Project A"),
        create_session(id: "s2", name: "Project B"),
        create_session(id: "s3", name: "Project C")
      ]

      sidebar =
        SessionSidebar.new(
          sessions: sessions,
          order: ["s1", "s2", "s3"],
          active_id: "s2",
          expanded: MapSet.new(["s2"]),
          width: 25
        )

      # Verify state
      assert SessionSidebar.session_count(sidebar) == 3
      assert SessionSidebar.has_active_session?(sidebar)
      assert SessionSidebar.expanded?(sidebar, "s2")
      refute SessionSidebar.expanded?(sidebar, "s1")

      # Render
      view = SessionSidebar.render(sidebar)
      assert view != nil
    end

    test "handles empty session list gracefully" do
      sidebar = SessionSidebar.new()

      assert SessionSidebar.session_count(sidebar) == 0
      refute SessionSidebar.has_active_session?(sidebar)

      view = SessionSidebar.render(sidebar)
      assert view != nil
    end

    test "handles session with very long name" do
      session =
        create_session(id: "s1", name: "This is a very long session name that exceeds limits")

      sidebar =
        SessionSidebar.new(
          sessions: [session],
          order: ["s1"],
          active_id: "s1"
        )

      title = SessionSidebar.build_title(sidebar, session)

      # Should be truncated with active indicator
      assert String.starts_with?(title, "→ ")
      assert String.length(title) <= 20
    end

    test "multiple sessions with mixed active and expanded states" do
      sessions = [
        create_session(id: "s1", name: "Active & Expanded"),
        create_session(id: "s2", name: "Collapsed"),
        create_session(id: "s3", name: "Expanded Not Active")
      ]

      sidebar =
        SessionSidebar.new(
          sessions: sessions,
          order: ["s1", "s2", "s3"],
          active_id: "s1",
          expanded: MapSet.new(["s1", "s3"])
        )

      # s1: active and expanded
      title1 = SessionSidebar.build_title(sidebar, Enum.at(sessions, 0))
      assert String.starts_with?(title1, "→ ")

      # s2: not active, not expanded
      title2 = SessionSidebar.build_title(sidebar, Enum.at(sessions, 1))
      refute String.starts_with?(title2, "→ ")
      refute SessionSidebar.expanded?(sidebar, "s2")

      # s3: not active, but expanded
      refute String.starts_with?(
               SessionSidebar.build_title(sidebar, Enum.at(sessions, 2)),
               "→ "
             )

      assert SessionSidebar.expanded?(sidebar, "s3")

      # Render works
      view = SessionSidebar.render(sidebar)
      assert view != nil
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  describe "edge cases" do
    test "session in order but not in sessions list" do
      session = create_session(id: "s1")
      sidebar = SessionSidebar.new(sessions: [session], order: ["s1", "s_missing"])

      # Should not crash
      view = SessionSidebar.render(sidebar)
      assert view != nil
    end

    test "empty order with non-empty sessions" do
      sessions = [create_session(id: "s1")]
      sidebar = SessionSidebar.new(sessions: sessions, order: [])

      # Should render with no sections
      view = SessionSidebar.render(sidebar)
      assert view != nil
    end

    test "duplicate session IDs in order" do
      session = create_session(id: "s1")
      sidebar = SessionSidebar.new(sessions: [session], order: ["s1", "s1"])

      # Should handle duplicates gracefully
      view = SessionSidebar.render(sidebar)
      assert view != nil
    end

    test "active_id not in sessions list" do
      session = create_session(id: "s1")
      sidebar = SessionSidebar.new(sessions: [session], order: ["s1"], active_id: "missing")

      # No session gets active indicator
      title = SessionSidebar.build_title(sidebar, session)
      refute String.starts_with?(title, "→ ")
    end

    test "expanded contains non-existent session IDs" do
      session = create_session(id: "s1")

      sidebar =
        SessionSidebar.new(
          sessions: [session],
          order: ["s1"],
          expanded: MapSet.new(["s1", "missing1", "missing2"])
        )

      # Should not crash
      view = SessionSidebar.render(sidebar)
      assert view != nil
    end

    test "very wide width" do
      session = create_session(id: "s1")
      sidebar = SessionSidebar.new(sessions: [session], order: ["s1"], width: 100)

      view = SessionSidebar.render(sidebar)
      assert view != nil
    end

    # Note: Very narrow widths (<20 chars) can cause issues with badge truncation
    # This is a known limitation of the accordion widget when width is insufficient
    # for icon + title + badge. Minimum practical width is 20 chars.
  end
end
