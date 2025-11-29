import {
  Chart,
  LineController,
  BarController,
  DoughnutController,
  PieController,
  CategoryScale,
  LinearScale,
  TimeScale,
  PointElement,
  LineElement,
  BarElement,
  ArcElement,
  Tooltip,
  Legend,
  Filler
} from 'chart.js'
import 'chartjs-adapter-date-fns'

Chart.register(
  LineController,
  BarController,
  DoughnutController,
  PieController,
  CategoryScale,
  LinearScale,
  TimeScale,
  PointElement,
  LineElement,
  BarElement,
  ArcElement,
  Tooltip,
  Legend,
  Filler
)

const ChartHook = {
  mounted() {
    const eventName = this.el.dataset.event
    
    if (!eventName) {
      console.error('[ChartHook] No data-event attribute found on element')
      return
    }

    this.handleEvent(eventName, (payload) => {
      this.updateChart(payload)
    })
  },

  updateChart(payload) {
    const ctx = this.el.getContext('2d')
    
    if (!ctx) {
      console.error('[ChartHook] Could not get canvas context')
      return
    }

    if (this.chart) {
      this.chart.data = payload
      this.chart.update()
    } else {
      this.chart = new Chart(ctx, {
        type: payload.type || 'line',
        data: {
          labels: payload.labels || [],
          datasets: payload.datasets || []
        },
        options: payload.options || {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: {
              display: true,
              position: 'top',
            },
            tooltip: {
              enabled: true,
            }
          }
        }
      })
    }
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }
}

export default ChartHook
