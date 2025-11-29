defmodule JidoHubWeb.UI.CommandPalette do
  @moduledoc """
  Command palette LiveComponent for keyboard-driven command execution.

  Provides a modal interface for searching and executing commands with
  keyboard shortcuts, filtering, and category grouping.
  """
  use JidoHubWeb, :live_component

  alias JidoHubWeb.Dashboard.Commands

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(
       selected_index: 0,
       filtered_commands: [],
       sequence_timeout_ref: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    filtered_commands = filter_commands(assigns.query, assigns.commands)
    grouped_commands = Commands.group_by_category(filtered_commands)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       filtered_commands: filtered_commands,
       grouped_commands: grouped_commands,
       selected_index: 0
     )}
  end

  @impl true
  def handle_event("filter", %{"value" => query}, socket) do
    filtered_commands = filter_commands(query, socket.assigns.commands)
    grouped_commands = Commands.group_by_category(filtered_commands)

    {:noreply,
     socket
     |> assign(
       query: query,
       filtered_commands: filtered_commands,
       grouped_commands: grouped_commands,
       selected_index: 0
     )
     |> push_event("update_query", %{query: query})}
  end

  @impl true
  def handle_event("execute", %{"id" => cmd_id}, socket) do
    cmd_atom = String.to_existing_atom(cmd_id)

    command =
      Enum.find(socket.assigns.commands, fn cmd ->
        cmd.id == cmd_atom
      end)

    if command do
      send(self(), {:ui_command_execute, command})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("close", _params, socket) do
    send(self(), :close_command_palette)
    {:noreply, socket}
  end

  @impl true
  def handle_event("handle_global_key", %{"key" => key} = params, socket)
      when socket.assigns.open == false do
    cond do
      # Cmd/Ctrl+K opens palette
      key in ["k", "K"] and (params["metaKey"] == true or params["ctrlKey"] == true) ->
        send(self(), :open_command_palette)
        {:noreply, socket}

      # Single letter keys start/continue sequence
      is_binary(key) and String.length(key) == 1 and key =~ ~r/^[a-z]$/ ->
        handle_keyboard_sequence(socket, key)

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("handle_global_key", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("handle_modal_key", %{"key" => key}, socket)
      when socket.assigns.open == true do
    case key do
      "ArrowDown" ->
        {:noreply, move_selection(socket, 1)}

      "ArrowUp" ->
        {:noreply, move_selection(socket, -1)}

      "Enter" ->
        execute_selected_command(socket)

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("handle_modal_key", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"#{@id}-wrapper"}>
      <%!-- Global keyboard listener (always listening) --%>
      <div
        id={"#{@id}-keyboard-listener"}
        phx-window-keydown="handle_global_key"
        phx-target={@myself}
        style="display: none;"
      />
      <div
        id={@id}
        phx-hook="Modal"
        data-show={to_string(@open)}
        phx-remove={JidoHubWeb.CoreComponents.hide_modal(@id)}
        class="relative z-50 hidden"
        phx-target={@myself}
      >
        <div
          id={"#{@id}-bg"}
          class="fixed inset-0 bg-black/50 backdrop-blur-sm transition-opacity"
          aria-hidden="true"
          phx-click="close"
          phx-target={@myself}
        />
        <div
          class="fixed inset-0 overflow-y-auto"
          aria-labelledby={"#{@id}-title"}
          role="dialog"
          aria-modal="true"
          tabindex="0"
        >
          <div class="flex min-h-full items-start justify-center pt-[15vh] p-4">
            <div class="w-full max-w-2xl transform transition-all">
              <.focus_wrap
                id={"#{@id}-container"}
                phx-window-keydown="handle_modal_key"
                phx-target={@myself}
                class="bg-base-200 rounded-xl border border-base-300/40 shadow-2xl overflow-hidden"
              >
                <div class="p-4 border-b border-base-300/40">
                  <div class="relative">
                    <.icon
                      name="hero-magnifying-glass"
                      class="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-base-content/50"
                    />
                    <input
                      id={"#{@id}-search-input"}
                      type="text"
                      name="query"
                      value={@query}
                      phx-keyup="filter"
                      phx-debounce="150"
                      phx-target={@myself}
                      placeholder="Type a command or search..."
                      class="input w-full pl-10 pr-4 bg-base-100 border-none focus:outline-none focus:ring-2 focus:ring-primary"
                      autofocus
                    />
                    <%!-- Sequence indicator --%>
                    <div
                      :if={@keyboard_sequence != ""}
                      class="absolute right-4 top-1/2 -translate-y-1/2 px-2 py-1 bg-blue-100 text-blue-700 text-sm rounded font-mono"
                    >
                      {@keyboard_sequence}
                    </div>
                  </div>
                </div>

                <div class="max-h-96 overflow-y-auto">
                  <%= if @grouped_commands == %{} do %>
                    <div class="p-8 text-center text-base-content/60">
                      <.icon name="hero-magnifying-glass" class="w-8 h-8 mx-auto mb-2 opacity-40" />
                      <p class="text-sm">No commands found</p>
                    </div>
                  <% else %>
                    <%= for {group, cmds} <- @grouped_commands do %>
                      <div class="py-2">
                        <div class="px-4 py-2 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                          {group}
                        </div>
                        <div>
                          <%= for {cmd, idx} <- Enum.with_index(cmds) do %>
                            <% # Calculate global index across all groups
                            prev_count =
                              @grouped_commands
                              |> Enum.take_while(fn {g, _} -> g != group end)
                              |> Enum.map(fn {_, cs} -> length(cs) end)
                              |> Enum.sum()

                            global_idx = prev_count + idx %>
                            <button
                              type="button"
                              phx-click="execute"
                              phx-value-id={cmd.id}
                              phx-target={@myself}
                              class={[
                                "w-full px-4 py-2.5 flex items-center gap-3 transition-colors text-left group",
                                global_idx == @selected_index && "bg-primary/10",
                                "hover:bg-base-300/40"
                              ]}
                            >
                              <.icon
                                :if={cmd.icon}
                                name={cmd.icon}
                                class="w-5 h-5 text-base-content/60 group-hover:text-base-content"
                              />
                              <span class="flex-1 text-sm">{cmd.label}</span>
                              <kbd
                                :if={cmd.shortcut}
                                class="px-2 py-0.5 text-xs font-semibold rounded border bg-base-100 border-base-300 text-base-content opacity-60 group-hover:opacity-100"
                              >
                                {cmd.shortcut}
                              </kbd>
                            </button>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                </div>

                <div class="px-4 py-3 border-t border-base-300/40 bg-base-300/20">
                  <div class="flex items-center justify-between text-xs text-base-content/60">
                    <div class="flex items-center gap-4">
                      <span class="flex items-center gap-1">
                        <kbd class="px-2 py-0.5 text-xs font-semibold rounded border bg-base-100 border-base-300 text-base-content">
                          ↑
                        </kbd>
                        <kbd class="px-2 py-0.5 text-xs font-semibold rounded border bg-base-100 border-base-300 text-base-content">
                          ↓
                        </kbd>
                        <span>navigate</span>
                      </span>
                      <span class="flex items-center gap-1">
                        <kbd class="px-2 py-0.5 text-xs font-semibold rounded border bg-base-100 border-base-300 text-base-content">
                          ↵
                        </kbd>
                        <span>select</span>
                      </span>
                    </div>
                    <span class="flex items-center gap-1">
                      <kbd class="px-2 py-0.5 text-xs font-semibold rounded border bg-base-100 border-base-300 text-base-content">
                        esc
                      </kbd>
                      <span>close</span>
                    </span>
                  </div>
                </div>
              </.focus_wrap>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp filter_commands("", commands), do: commands

  defp filter_commands(query, commands) do
    query_lower = String.downcase(query)

    Enum.filter(commands, fn cmd ->
      String.contains?(String.downcase(cmd.label), query_lower)
    end)
  end

  defp handle_keyboard_sequence(socket, key) do
    sequence = socket.assigns.keyboard_sequence <> key

    # Cancel previous timeout
    if socket.assigns.sequence_timeout_ref do
      Process.cancel_timer(socket.assigns.sequence_timeout_ref)
    end

    # Check if sequence matches a shortcut
    case Map.get(socket.assigns.keyboard_shortcuts, sequence) do
      nil ->
        # Wait for more keys (3 second timeout)
        ref = Process.send_after(self(), :reset_keyboard_sequence, 3000)
        {:noreply, assign(socket, keyboard_sequence: sequence, sequence_timeout_ref: ref)}

      cmd ->
        # Execute matched command
        send(self(), {:execute_keyboard_command, cmd})
        {:noreply, assign(socket, keyboard_sequence: "", sequence_timeout_ref: nil)}
    end
  end

  defp move_selection(socket, direction) do
    total = length(socket.assigns.filtered_commands)

    if total > 0 do
      new_index =
        (socket.assigns.selected_index + direction)
        |> max(0)
        |> min(total - 1)

      assign(socket, selected_index: new_index)
    else
      socket
    end
  end

  defp execute_selected_command(socket) do
    total = length(socket.assigns.filtered_commands)

    if total > 0 and socket.assigns.selected_index < total do
      cmd = Enum.at(socket.assigns.filtered_commands, socket.assigns.selected_index)
      send(self(), {:ui_command_execute, cmd})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end
end
