defmodule JidoHubWeb.Settings.Components do
  @moduledoc """
  Reusable components for settings pages.
  """
  use JidoHubWeb, :html

  alias JidoHubWeb.Menus

  @doc """
  Renders the settings sidebar navigation.
  """
  attr :current_path, :string, required: true
  attr :rest, :global

  def settings_sidebar(assigns) do
    assigns = assign(assigns, :menu_items, Menus.items(:settings))

    ~H"""
    <div class="w-64 border-r border-base-300 bg-base-200 flex flex-col" {@rest}>
      <div class="p-4 border-b border-base-300">
        <.link
          navigate="/dashboard"
          class="flex items-center gap-2 text-sm text-base-content/70 hover:text-base-content transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4" />
          <span>Back to app</span>
        </.link>
      </div>

      <nav class="flex-1 p-3 space-y-1">
        <.settings_nav_item
          :for={item <- @menu_items}
          icon={item.icon}
          label={item.label}
          active={Menus.active?(@current_path, item)}
          navigate={item.to}
        />

        <div class="pt-4">
          <div class="text-xs font-semibold text-base-content/50 px-3 py-2">Your Pods</div>
        </div>
      </nav>
    </div>
    """
  end

  @doc """
  Renders a settings navigation item.
  """
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :navigate, :string, required: true

  def settings_nav_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors",
        if(@active,
          do: "bg-primary text-primary-content",
          else: "text-base-content/70 hover:bg-base-300 hover:text-base-content"
        )
      ]}
    >
      <.icon name={@icon} class="w-4 h-4" />
      <span>{@label}</span>
    </.link>
    """
  end

  @doc """
  Renders a settings page header.
  """
  attr :title, :string, required: true
  attr :description, :string, default: nil

  def settings_header(assigns) do
    ~H"""
    <div class="mb-8">
      <h1 class="text-3xl font-bold mb-2">{@title}</h1>
      <p :if={@description} class="text-base-content/70">{@description}</p>
    </div>
    """
  end

  @doc """
  Renders a settings section card.
  """
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def settings_section(assigns) do
    ~H"""
    <div class={["card bg-base-200", @class]}>
      <div class="card-body">
        <div class="mb-4">
          <h2 class="card-title text-lg">{@title}</h2>
          <p :if={@description} class="text-sm text-base-content/70 mt-1">{@description}</p>
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a form field group with consistent spacing.
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def field_group(assigns) do
    ~H"""
    <div class={["space-y-4", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a toggle switch with label.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :description, :string, default: nil
  attr :checked, :boolean, default: false
  attr :name, :string, required: true
  attr :rest, :global

  def toggle_field(assigns) do
    ~H"""
    <div class="form-control">
      <label class="label cursor-pointer justify-start gap-4">
        <input
          type="checkbox"
          id={@id}
          name={@name}
          class="toggle toggle-primary"
          checked={@checked}
          {@rest}
        />
        <div>
          <span class="label-text font-medium">{@label}</span>
          <p :if={@description} class="text-xs text-base-content/60 mt-0.5">{@description}</p>
        </div>
      </label>
    </div>
    """
  end

  @doc """
  Renders a select dropdown with label.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :options, :list, required: true
  attr :value, :string, default: nil
  attr :description, :string, default: nil
  attr :rest, :global

  def select_field(assigns) do
    ~H"""
    <div class="form-control w-full max-w-xs">
      <label class="label">
        <span class="label-text font-medium">{@label}</span>
      </label>
      <select id={@id} name={@name} class="select select-bordered w-full" {@rest}>
        <option
          :for={opt <- @options}
          value={if is_binary(opt), do: opt, else: elem(opt, 1)}
          selected={if(is_binary(opt), do: opt == @value, else: elem(opt, 1) == @value)}
        >
          {if is_binary(opt), do: opt, else: elem(opt, 0)}
        </option>
      </select>
      <label :if={@description} class="label">
        <span class="label-text-alt text-base-content/60">{@description}</span>
      </label>
    </div>
    """
  end

  @doc """
  Renders a text input with label.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :type, :string, default: "text"
  attr :value, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :description, :string, default: nil
  attr :required, :boolean, default: false
  attr :rest, :global

  def text_field(assigns) do
    ~H"""
    <div class="form-control w-full">
      <label class="label">
        <span class="label-text font-medium">
          {@label}
          <span :if={@required} class="text-error">*</span>
        </span>
      </label>
      <input
        type={@type}
        id={@id}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        class="input input-bordered w-full"
        required={@required}
        {@rest}
      />
      <label :if={@description} class="label">
        <span class="label-text-alt text-base-content/60">{@description}</span>
      </label>
    </div>
    """
  end

  @doc """
  Renders action buttons for forms.
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def form_actions(assigns) do
    ~H"""
    <div class={["flex items-center gap-3 mt-6", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
