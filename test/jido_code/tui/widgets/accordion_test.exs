defmodule JidoCode.TUI.Widgets.AccordionTest do
  use ExUnit.Case, async: true

  alias JidoCode.TUI.Widgets.Accordion
  alias TermUI.Renderer.Style

  # ============================================================================
  # Constructor & Initialization Tests
  # ============================================================================

  describe "new/1" do
    test "creates empty accordion with default values" do
      accordion = Accordion.new()

      assert accordion.sections == []
      assert accordion.active_ids == MapSet.new()
      assert accordion.indent == 2
      assert is_map(accordion.style)
    end

    test "creates accordion with sections" do
      sections = [
        %{id: :files, title: "Files"},
        %{id: :tools, title: "Tools"}
      ]

      accordion = Accordion.new(sections: sections)

      assert length(accordion.sections) == 2
      assert Enum.at(accordion.sections, 0).id == :files
      assert Enum.at(accordion.sections, 1).id == :tools
    end

    test "creates accordion with initially expanded sections" do
      sections = [%{id: :files, title: "Files"}]
      accordion = Accordion.new(sections: sections, active_ids: [:files])

      assert MapSet.member?(accordion.active_ids, :files)
    end

    test "normalizes sections to include default fields" do
      sections = [%{id: :files, title: "Files"}]
      accordion = Accordion.new(sections: sections)

      section = Enum.at(accordion.sections, 0)
      assert section.id == :files
      assert section.title == "Files"
      assert section.content == []
      assert section.badge == nil
      assert section.icon_open == "▼"
      assert section.icon_closed == "▶"
    end

    test "preserves custom icon values in sections" do
      sections = [
        %{id: :files, title: "Files", icon_open: "↓", icon_closed: "→"}
      ]

      accordion = Accordion.new(sections: sections)
      section = Enum.at(accordion.sections, 0)

      assert section.icon_open == "↓"
      assert section.icon_closed == "→"
    end

    test "accepts custom indent value" do
      accordion = Accordion.new(indent: 4)

      assert accordion.indent == 4
    end

    test "accepts custom style configuration" do
      style = %{title_style: Style.new(fg: :cyan)}
      accordion = Accordion.new(style: style)

      assert accordion.style.title_style == Style.new(fg: :cyan)
    end
  end

  describe "normalize_section/1" do
    test "adds default values for missing fields" do
      section = %{id: :files, title: "Files"}
      normalized = Accordion.normalize_section(section)

      assert normalized.id == :files
      assert normalized.title == "Files"
      assert normalized.content == []
      assert normalized.badge == nil
      assert normalized.icon_open == "▼"
      assert normalized.icon_closed == "▶"
    end

    test "preserves existing field values" do
      section = %{
        id: :files,
        title: "Files",
        content: [:some_content],
        badge: "12",
        icon_open: "↓",
        icon_closed: "→"
      }

      normalized = Accordion.normalize_section(section)

      assert normalized.content == [:some_content]
      assert normalized.badge == "12"
      assert normalized.icon_open == "↓"
      assert normalized.icon_closed == "→"
    end

    test "raises if :id is missing" do
      assert_raise KeyError, fn ->
        Accordion.normalize_section(%{title: "Files"})
      end
    end

    test "uses empty string for missing title" do
      section = %{id: :files}
      normalized = Accordion.normalize_section(section)

      assert normalized.title == ""
    end
  end

  # ============================================================================
  # Expansion API Tests
  # ============================================================================

  describe "expand/2" do
    test "expands a section by ID" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      expanded = Accordion.expand(accordion, :files)

      assert MapSet.member?(expanded.active_ids, :files)
    end

    test "does not duplicate if section already expanded" do
      accordion =
        Accordion.new(sections: [%{id: :files, title: "Files"}], active_ids: [:files])

      expanded = Accordion.expand(accordion, :files)

      assert MapSet.size(expanded.active_ids) == 1
    end

    test "can expand multiple sections" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"}
          ]
        )

      expanded = accordion |> Accordion.expand(:files) |> Accordion.expand(:tools)

      assert MapSet.member?(expanded.active_ids, :files)
      assert MapSet.member?(expanded.active_ids, :tools)
    end

    test "expands non-existent section ID without error" do
      accordion = Accordion.new()
      expanded = Accordion.expand(accordion, :non_existent)

      assert MapSet.member?(expanded.active_ids, :non_existent)
    end
  end

  describe "collapse/2" do
    test "collapses an expanded section" do
      accordion = Accordion.new(active_ids: [:files])
      collapsed = Accordion.collapse(accordion, :files)

      refute MapSet.member?(collapsed.active_ids, :files)
    end

    test "does nothing if section not expanded" do
      accordion = Accordion.new()
      collapsed = Accordion.collapse(accordion, :files)

      assert MapSet.size(collapsed.active_ids) == 0
    end

    test "can collapse one of multiple expanded sections" do
      accordion = Accordion.new(active_ids: [:files, :tools])
      collapsed = Accordion.collapse(accordion, :files)

      refute MapSet.member?(collapsed.active_ids, :files)
      assert MapSet.member?(collapsed.active_ids, :tools)
    end
  end

  describe "toggle/2" do
    test "expands a collapsed section" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      toggled = Accordion.toggle(accordion, :files)

      assert MapSet.member?(toggled.active_ids, :files)
    end

    test "collapses an expanded section" do
      accordion =
        Accordion.new(sections: [%{id: :files, title: "Files"}], active_ids: [:files])

      toggled = Accordion.toggle(accordion, :files)

      refute MapSet.member?(toggled.active_ids, :files)
    end

    test "toggles multiple times" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])

      toggled1 = Accordion.toggle(accordion, :files)
      assert MapSet.member?(toggled1.active_ids, :files)

      toggled2 = Accordion.toggle(toggled1, :files)
      refute MapSet.member?(toggled2.active_ids, :files)

      toggled3 = Accordion.toggle(toggled2, :files)
      assert MapSet.member?(toggled3.active_ids, :files)
    end
  end

  describe "expand_all/1" do
    test "expands all sections" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"},
            %{id: :context, title: "Context"}
          ]
        )

      expanded = Accordion.expand_all(accordion)

      assert MapSet.member?(expanded.active_ids, :files)
      assert MapSet.member?(expanded.active_ids, :tools)
      assert MapSet.member?(expanded.active_ids, :context)
      assert MapSet.size(expanded.active_ids) == 3
    end

    test "works on empty accordion" do
      accordion = Accordion.new()
      expanded = Accordion.expand_all(accordion)

      assert MapSet.size(expanded.active_ids) == 0
    end

    test "replaces existing active_ids" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"}
          ],
          active_ids: [:files]
        )

      expanded = Accordion.expand_all(accordion)

      assert MapSet.size(expanded.active_ids) == 2
    end
  end

  describe "collapse_all/1" do
    test "collapses all sections" do
      accordion = Accordion.new(active_ids: [:files, :tools, :context])
      collapsed = Accordion.collapse_all(accordion)

      assert MapSet.size(collapsed.active_ids) == 0
    end

    test "works on already collapsed accordion" do
      accordion = Accordion.new()
      collapsed = Accordion.collapse_all(accordion)

      assert MapSet.size(collapsed.active_ids) == 0
    end
  end

  # ============================================================================
  # Section Management Tests
  # ============================================================================

  describe "add_section/2" do
    test "adds section to empty accordion" do
      accordion = Accordion.new()
      section = %{id: :files, title: "Files"}
      updated = Accordion.add_section(accordion, section)

      assert Accordion.section_count(updated) == 1
      assert Enum.at(updated.sections, 0).id == :files
    end

    test "adds section to existing sections" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      section = %{id: :tools, title: "Tools"}
      updated = Accordion.add_section(accordion, section)

      assert Accordion.section_count(updated) == 2
    end

    test "normalizes section when adding" do
      accordion = Accordion.new()
      section = %{id: :files, title: "Files"}
      updated = Accordion.add_section(accordion, section)

      added = Enum.at(updated.sections, 0)
      assert added.content == []
      assert added.badge == nil
    end

    test "adds section at end of list" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"}
          ]
        )

      section = %{id: :context, title: "Context"}
      updated = Accordion.add_section(accordion, section)

      assert Enum.at(updated.sections, 2).id == :context
    end
  end

  describe "remove_section/2" do
    test "removes section by ID" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"}
          ]
        )

      updated = Accordion.remove_section(accordion, :files)

      assert Accordion.section_count(updated) == 1
      assert Enum.at(updated.sections, 0).id == :tools
    end

    test "removes section from active_ids if expanded" do
      accordion =
        Accordion.new(
          sections: [%{id: :files, title: "Files"}],
          active_ids: [:files]
        )

      updated = Accordion.remove_section(accordion, :files)

      refute MapSet.member?(updated.active_ids, :files)
    end

    test "does nothing if section ID not found" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      updated = Accordion.remove_section(accordion, :non_existent)

      assert Accordion.section_count(updated) == 1
    end

    test "removes all matching sections with same ID" do
      # Edge case: multiple sections with same ID
      accordion = %Accordion{
        sections: [
          %{
            id: :files,
            title: "Files",
            content: [],
            badge: nil,
            icon_open: "▼",
            icon_closed: "▶"
          },
          %{
            id: :files,
            title: "Files 2",
            content: [],
            badge: nil,
            icon_open: "▼",
            icon_closed: "▶"
          }
        ],
        active_ids: MapSet.new(),
        style: %{},
        indent: 2
      }

      updated = Accordion.remove_section(accordion, :files)

      assert Accordion.section_count(updated) == 0
    end
  end

  describe "update_section/3" do
    test "updates section title" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      updated = Accordion.update_section(accordion, :files, %{title: "My Files"})

      section = Accordion.get_section(updated, :files)
      assert section.title == "My Files"
    end

    test "updates section badge" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      updated = Accordion.update_section(accordion, :files, %{badge: "12"})

      section = Accordion.get_section(updated, :files)
      assert section.badge == "12"
    end

    test "updates multiple fields" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])

      updated =
        Accordion.update_section(accordion, :files, %{
          title: "My Files",
          badge: "12",
          icon_open: "↓"
        })

      section = Accordion.get_section(updated, :files)
      assert section.title == "My Files"
      assert section.badge == "12"
      assert section.icon_open == "↓"
    end

    test "does nothing if section ID not found" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      updated = Accordion.update_section(accordion, :non_existent, %{title: "New"})

      # Original section unchanged
      section = Accordion.get_section(updated, :files)
      assert section.title == "Files"
    end

    test "only updates matching section" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"}
          ]
        )

      updated = Accordion.update_section(accordion, :files, %{title: "My Files"})

      files_section = Accordion.get_section(updated, :files)
      tools_section = Accordion.get_section(updated, :tools)

      assert files_section.title == "My Files"
      assert tools_section.title == "Tools"
    end
  end

  # ============================================================================
  # Accessor Function Tests
  # ============================================================================

  describe "expanded?/2" do
    test "returns true for expanded section" do
      accordion = Accordion.new(active_ids: [:files])

      assert Accordion.expanded?(accordion, :files)
    end

    test "returns false for collapsed section" do
      accordion = Accordion.new()

      refute Accordion.expanded?(accordion, :files)
    end

    test "returns false for non-existent section" do
      accordion = Accordion.new()

      refute Accordion.expanded?(accordion, :non_existent)
    end
  end

  describe "get_section/2" do
    test "returns section by ID" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      section = Accordion.get_section(accordion, :files)

      assert section.id == :files
      assert section.title == "Files"
    end

    test "returns nil if section not found" do
      accordion = Accordion.new()
      section = Accordion.get_section(accordion, :non_existent)

      assert section == nil
    end

    test "returns first matching section if multiple with same ID" do
      accordion = %Accordion{
        sections: [
          %{
            id: :files,
            title: "Files 1",
            content: [],
            badge: nil,
            icon_open: "▼",
            icon_closed: "▶"
          },
          %{
            id: :files,
            title: "Files 2",
            content: [],
            badge: nil,
            icon_open: "▼",
            icon_closed: "▶"
          }
        ],
        active_ids: MapSet.new(),
        style: %{},
        indent: 2
      }

      section = Accordion.get_section(accordion, :files)

      assert section.title == "Files 1"
    end
  end

  describe "section_count/1" do
    test "returns 0 for empty accordion" do
      accordion = Accordion.new()

      assert Accordion.section_count(accordion) == 0
    end

    test "returns correct count for accordion with sections" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"}
          ]
        )

      assert Accordion.section_count(accordion) == 2
    end
  end

  describe "expanded_count/1" do
    test "returns 0 when no sections expanded" do
      accordion = Accordion.new()

      assert Accordion.expanded_count(accordion) == 0
    end

    test "returns correct count of expanded sections" do
      accordion = Accordion.new(active_ids: [:files, :tools])

      assert Accordion.expanded_count(accordion) == 2
    end

    test "count matches number of expanded sections after operations" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"},
            %{id: :context, title: "Context"}
          ]
        )

      expanded = accordion |> Accordion.expand(:files) |> Accordion.expand(:tools)

      assert Accordion.expanded_count(expanded) == 2
    end
  end

  describe "section_ids/1" do
    test "returns empty list for empty accordion" do
      accordion = Accordion.new()

      assert Accordion.section_ids(accordion) == []
    end

    test "returns list of all section IDs" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"}
          ]
        )

      ids = Accordion.section_ids(accordion)

      assert ids == [:files, :tools]
    end

    test "maintains section order" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :context, title: "Context"},
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"}
          ]
        )

      ids = Accordion.section_ids(accordion)

      assert ids == [:context, :files, :tools]
    end
  end

  # ============================================================================
  # Rendering Tests
  # ============================================================================

  describe "render/2" do
    test "renders empty state for accordion with no sections" do
      accordion = Accordion.new()
      view = Accordion.render(accordion, 20)

      # Should be a text element with "(no sections)"
      assert view != nil
    end

    test "renders sections in collapsed state" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"}
          ]
        )

      view = Accordion.render(accordion, 20)

      # Should be a vertical stack
      assert view != nil
    end

    test "renders sections in expanded state" do
      accordion =
        Accordion.new(
          sections: [%{id: :files, title: "Files", content: []}],
          active_ids: [:files]
        )

      view = Accordion.render(accordion, 20)

      assert view != nil
    end

    test "renders with custom width" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])

      view1 = Accordion.render(accordion, 20)
      view2 = Accordion.render(accordion, 40)

      assert view1 != nil
      assert view2 != nil
    end

    test "renders section with badge" do
      accordion =
        Accordion.new(sections: [%{id: :files, title: "Files", badge: "12"}])

      view = Accordion.render(accordion, 20)

      assert view != nil
    end

    test "renders expanded section with content" do
      import TermUI.Component.Helpers

      content = [text("file1.ex"), text("file2.ex")]

      accordion =
        Accordion.new(
          sections: [%{id: :files, title: "Files", content: content}],
          active_ids: [:files]
        )

      view = Accordion.render(accordion, 20)

      assert view != nil
    end

    test "renders multiple sections with mixed expansion state" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"},
            %{id: :context, title: "Context"}
          ],
          active_ids: [:files, :context]
        )

      view = Accordion.render(accordion, 20)

      assert view != nil
    end

    test "uses default width if not specified" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])

      view = Accordion.render(accordion)

      assert view != nil
    end
  end

  # ============================================================================
  # Icon and Badge Tests
  # ============================================================================

  describe "icons" do
    test "collapsed section shows closed icon" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])

      # Render and check state (icon rendering happens in private functions)
      section = Accordion.get_section(accordion, :files)
      refute Accordion.expanded?(accordion, :files)
      assert section.icon_closed == "▶"
    end

    test "expanded section shows open icon" do
      accordion =
        Accordion.new(
          sections: [%{id: :files, title: "Files"}],
          active_ids: [:files]
        )

      section = Accordion.get_section(accordion, :files)
      assert Accordion.expanded?(accordion, :files)
      assert section.icon_open == "▼"
    end

    test "custom icons are preserved" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files", icon_open: "↓", icon_closed: "→"}
          ]
        )

      section = Accordion.get_section(accordion, :files)
      assert section.icon_open == "↓"
      assert section.icon_closed == "→"
    end
  end

  describe "badges" do
    test "section without badge has nil badge" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])

      section = Accordion.get_section(accordion, :files)
      assert section.badge == nil
    end

    test "section with badge preserves badge value" do
      accordion =
        Accordion.new(sections: [%{id: :files, title: "Files", badge: "12"}])

      section = Accordion.get_section(accordion, :files)
      assert section.badge == "12"
    end

    test "badge can be updated" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      updated = Accordion.update_section(accordion, :files, %{badge: "5"})

      section = Accordion.get_section(updated, :files)
      assert section.badge == "5"
    end

    test "badge can be cleared" do
      accordion =
        Accordion.new(sections: [%{id: :files, title: "Files", badge: "12"}])

      updated = Accordion.update_section(accordion, :files, %{badge: nil})

      section = Accordion.get_section(updated, :files)
      assert section.badge == nil
    end
  end

  # ============================================================================
  # Content and Indentation Tests
  # ============================================================================

  describe "content" do
    test "section with empty content list" do
      accordion = Accordion.new(sections: [%{id: :files, title: "Files", content: []}])

      section = Accordion.get_section(accordion, :files)
      assert section.content == []
    end

    test "section with content elements" do
      import TermUI.Component.Helpers

      content = [text("item1"), text("item2")]

      accordion =
        Accordion.new(sections: [%{id: :files, title: "Files", content: content}])

      section = Accordion.get_section(accordion, :files)
      assert length(section.content) == 2
    end

    test "content can be updated" do
      import TermUI.Component.Helpers

      accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      new_content = [text("file1.ex")]
      updated = Accordion.update_section(accordion, :files, %{content: new_content})

      section = Accordion.get_section(updated, :files)
      assert section.content == new_content
    end
  end

  describe "indentation" do
    test "default indent is 2 spaces" do
      accordion = Accordion.new()

      assert accordion.indent == 2
    end

    test "custom indent value is preserved" do
      accordion = Accordion.new(indent: 4)

      assert accordion.indent == 4
    end

    test "indent can be 0" do
      accordion = Accordion.new(indent: 0)

      assert accordion.indent == 0
    end
  end

  # ============================================================================
  # Style Tests
  # ============================================================================

  describe "styling" do
    test "default style has all nil values" do
      accordion = Accordion.new()

      assert accordion.style.title_style == nil
      assert accordion.style.badge_style == nil
      assert accordion.style.content_style == nil
      assert accordion.style.icon_style == nil
    end

    test "custom styles are preserved" do
      style = %{
        title_style: Style.new(fg: :cyan),
        badge_style: Style.new(fg: :yellow)
      }

      accordion = Accordion.new(style: style)

      assert accordion.style.title_style == Style.new(fg: :cyan)
      assert accordion.style.badge_style == Style.new(fg: :yellow)
    end

    test "partial style updates merge with defaults" do
      style = %{title_style: Style.new(fg: :cyan)}
      accordion = Accordion.new(style: style)

      assert accordion.style.title_style == Style.new(fg: :cyan)
      assert accordion.style.badge_style == nil
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "integration scenarios" do
    test "create accordion, add sections, expand some, render" do
      accordion = Accordion.new()

      # Add sections
      accordion =
        accordion
        |> Accordion.add_section(%{id: :files, title: "Files", badge: "12"})
        |> Accordion.add_section(%{id: :tools, title: "Tools", badge: "5"})
        |> Accordion.add_section(%{id: :context, title: "Context"})

      # Expand some sections
      accordion = accordion |> Accordion.expand(:files) |> Accordion.expand(:context)

      # Verify state
      assert Accordion.section_count(accordion) == 3
      assert Accordion.expanded_count(accordion) == 2
      assert Accordion.expanded?(accordion, :files)
      refute Accordion.expanded?(accordion, :tools)
      assert Accordion.expanded?(accordion, :context)

      # Render
      view = Accordion.render(accordion, 20)
      assert view != nil
    end

    test "toggle workflow" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"}
          ]
        )

      # Toggle first section twice
      accordion =
        accordion |> Accordion.toggle(:files) |> Accordion.toggle(:files)

      refute Accordion.expanded?(accordion, :files)

      # Toggle both sections
      accordion =
        accordion |> Accordion.toggle(:files) |> Accordion.toggle(:tools)

      assert Accordion.expanded?(accordion, :files)
      assert Accordion.expanded?(accordion, :tools)
    end

    test "expand all then collapse all" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"},
            %{id: :context, title: "Context"}
          ]
        )

      expanded = Accordion.expand_all(accordion)
      assert Accordion.expanded_count(expanded) == 3

      collapsed = Accordion.collapse_all(expanded)
      assert Accordion.expanded_count(collapsed) == 0
    end

    test "remove section clears its expansion state" do
      accordion =
        Accordion.new(
          sections: [
            %{id: :files, title: "Files"},
            %{id: :tools, title: "Tools"}
          ],
          active_ids: [:files, :tools]
        )

      updated = Accordion.remove_section(accordion, :files)

      assert Accordion.section_count(updated) == 1
      assert Accordion.expanded_count(updated) == 1
      refute Accordion.expanded?(updated, :files)
      assert Accordion.expanded?(updated, :tools)
    end

    test "update section preserves expansion state" do
      accordion =
        Accordion.new(
          sections: [%{id: :files, title: "Files"}],
          active_ids: [:files]
        )

      updated = Accordion.update_section(accordion, :files, %{title: "My Files"})

      assert Accordion.expanded?(updated, :files)
      section = Accordion.get_section(updated, :files)
      assert section.title == "My Files"
    end
  end
end
