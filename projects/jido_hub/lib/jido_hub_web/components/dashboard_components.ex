defmodule JidoHubWeb.Components.DashboardComponents do
  @moduledoc """
  A set of components for showing stats in a dashboard.
  """
  use Phoenix.Component

  import JidoHubWeb.Components.Charts
  import JidoHubWeb.CoreComponents

  def dashboard_panel(assigns) do
    assigns =
      assigns
      |> assign_new(:class, fn -> "" end)
      |> assign_new(:heading, fn -> nil end)

    ~H"""
    <div class={[
      "card bg-base-100 border border-base-300 rounded-lg shadow-sm",
      @class
    ]}>
      <%= if @heading do %>
        <div class="card-body p-0">
          <div class="border-b border-base-300 px-5 py-3">
            <h3 class="text-lg font-semibold">{@heading}</h3>
          </div>
          <div class="p-0">
            {render_slot(@inner_block)}
          </div>
        </div>
      <% else %>
        <div class="card-body p-0">
          {render_slot(@inner_block)}
        </div>
      <% end %>
    </div>
    """
  end

  def dashboard_stat(assigns) do
    assigns =
      assigns
      |> assign_new(:class, fn -> "" end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:stat, fn -> nil end)
      |> assign_new(:icon, fn -> nil end)
      |> assign_new(:chart_event, fn -> nil end)
      |> assign_new(:chart_datasets, fn -> [] end)
      |> assign_new(:chart_labels, fn -> [] end)
      |> assign_new(:percentage_change, fn -> nil end)
      |> assign_new(:empty?, fn -> false end)
      |> assign_new(:extra_assigns, fn ->
        assigns_to_attributes(assigns, ~w(
          icon
          class
          label
          stat
          chart_datasets
          percentage_change
        )a)
      end)

    ~H"""
    <div
      class={[
        "card bg-base-100 border border-base-300 rounded-lg shadow-sm p-5 sm:p-6",
        @class
      ]}
      {@extra_assigns}
    >
      <div class="flex flex-col">
        <div class="inline-flex">
          <%= if @icon do %>
            <div class="mr-5 rounded-md bg-primary/10 p-3">
              <.icon name={@icon} class="h-8 w-8 text-primary" />
            </div>
          <% end %>
          <div class="flex flex-col overflow-hidden">
            <dt class="truncate text-sm font-medium text-base-content/60">
              {@label}
            </dt>
            <dd class="flex items-baseline gap-1 overflow-hidden text-3xl font-semibold sm:gap-2">
              {@stat}
              <.percentage_change percentage={@percentage_change} />
              <span class="truncate text-sm font-light text-base-content/50">
                vs last period
              </span>
            </dd>
          </div>
        </div>
      </div>
      <div class="pt-5">
        <.no_data :if={@empty?} class="h-16 text-sm" />
        <.chart_js
          :if={not @empty?}
          class="h-16 w-full"
          event={@chart_event}
          options={
            %{
              type: "line",
              options: %{
                maintainAspectRatio: false,
                responsive: true,
                tension: 0.4,
                pointRadius: 0,
                scales: %{
                  y: %{
                    grid: %{
                      display: false,
                      drawBorder: false,
                      drawTicks: false
                    },
                    ticks: %{
                      display: false
                    }
                  },
                  x: %{
                    grid: %{
                      display: false,
                      drawBorder: false
                    },
                    ticks: %{
                      display: false
                    }
                  }
                },
                plugins: %{
                  legend: %{
                    display: false
                  }
                },
                interaction: %{
                  intersect: false,
                  mode: "nearest"
                }
              }
            }
          }
        />
      </div>
    </div>
    """
  end

  def percentage_change(%{percentage: nil} = assigns), do: ~H""

  def percentage_change(%{percentage: percentage} = assigns) when percentage >= 0 do
    ~H"""
    <span class="ml-2 flex items-baseline text-sm font-semibold text-success">
      <svg
        class="h-5 w-5 shrink-0 self-center"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 20 20"
        fill="currentColor"
        aria-hidden="true"
      >
        <path
          fill-rule="evenodd"
          d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z"
          clip-rule="evenodd"
        />
      </svg>
      {@percentage}%
    </span>
    """
  end

  def percentage_change(%{percentage: percentage} = assigns) when percentage < 0 do
    ~H"""
    <span class="flex items-baseline text-sm font-semibold text-error">
      <svg
        class="h-5 w-5 shrink-0 self-center"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 20 20"
        fill="currentColor"
        aria-hidden="true"
      >
        <path
          fill-rule="evenodd"
          d="M14.707 10.293a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L9 12.586V5a1 1 0 012 0v7.586l2.293-2.293a1 1 0 011.414 0z"
          clip-rule="evenodd"
        />
      </svg>
      {@percentage}%
    </span>
    """
  end

  attr :heading, :string, required: true, doc: "The heading of the panel."
  attr :chart_event, :string, required: true, doc: "The event to push to the live view socket."
  attr :empty, :boolean, default: false, doc: "Whether the data is empty."
  attr :class, :string, default: "", doc: "The class for the panel."
  attr :graph_type, :string, default: "bar", doc: "The type of chart."

  def dashboard_graph(assigns) do
    ~H"""
    <.dashboard_panel heading={@heading} class={@class}>
      <.no_data :if={@empty} />
      <.chart_js
        :if={not @empty}
        class="h-96 p-5"
        event={@chart_event}
        options={
          %{
            type: "#{@graph_type}",
            options: %{
              maintainAspectRatio: false,
              layout: %{
                padding: %{
                  top: 12,
                  bottom: 16,
                  left: 20,
                  right: 20
                }
              },
              tension: 0.4,
              scales: %{
                y: %{
                  grid: %{
                    drawBorder: false
                  },
                  ticks: %{
                    maxTicksLimit: 5,
                    color: "hsl(var(--bc) / 0.6)",
                    font: %{
                      size: 14
                    }
                  }
                },
                x: %{
                  type: "time",
                  time: %{
                    parser: "MM-yyyy",
                    unit: "month",
                    displayFormats: %{
                      month: "MMM"
                    }
                  },
                  ticks: %{
                    color: "hsl(var(--bc) / 0.6)",
                    font: %{
                      size: 14
                    }
                  },
                  grid: %{
                    display: false,
                    drawBorder: false
                  }
                }
              },
              plugins: %{
                legend: %{
                  labels: %{
                    color: "hsl(var(--bc) / 0.6)",
                    font: %{
                      size: 14
                    }
                  }
                }
              }
            }
          }
        }
      />
    </.dashboard_panel>
    """
  end

  attr :heading, :string, required: true, doc: "The heading of the panel."
  attr :chart_event, :string, required: true, doc: "The event for LiveView data loading."
  attr :class, :string, default: "", doc: "The class for the panel."
  attr :empty, :boolean, default: false, doc: "Whether the data is empty."

  def dashboard_donut(assigns) do
    ~H"""
    <.dashboard_panel class="col-span-4 md:col-span-2" heading={@heading}>
      <.no_data :if={@empty} />
      <.chart_js
        :if={not @empty}
        class="mb-5 h-96 p-2"
        event={@chart_event}
        options={
          %{
            type: "doughnut",
            options: %{
              responsive: true,
              maintainAspectRatio: true,
              cutout: "80%",
              layout: %{
                padding: %{
                  top: 24,
                  bottom: 24
                }
              },
              scales: %{
                y: %{
                  grid: %{
                    display: false,
                    drawBorder: false,
                    drawTicks: false
                  },
                  ticks: %{
                    display: false,
                    color: "hsl(var(--bc) / 0.6)",
                    font: %{
                      size: 14
                    }
                  }
                },
                x: %{
                  grid: %{
                    display: false,
                    drawBorder: false
                  },
                  ticks: %{
                    display: false,
                    color: "hsl(var(--bc) / 0.6)",
                    font: %{
                      size: 14
                    }
                  }
                }
              },
              plugins: %{
                legend: %{
                  labels: %{
                    color: "hsl(var(--bc) / 0.6)",
                    font: %{
                      size: 14
                    }
                  }
                }
              }
            }
          }
        }
      />
    </.dashboard_panel>
    """
  end

  attr :class, :string, default: "h-96 text-lg", doc: "The class for the panel."

  defp no_data(assigns) do
    ~H"""
    <div class={["flex items-center justify-center", @class]}>
      <p class="font-normal text-base-content/40">
        No data available
      </p>
    </div>
    """
  end
end
