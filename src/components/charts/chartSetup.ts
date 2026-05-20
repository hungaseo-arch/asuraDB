import {
  Chart as ChartJS,
  ArcElement,
  LineElement,
  PointElement,
  BarElement,
  CategoryScale,
  LinearScale,
  Filler,
  Tooltip,
  Legend,
  Title,
} from 'chart.js';

// One-time Chart.js registration. Imported by every chart component.
// Mirrors what we got "for free" from recharts in the React project.
ChartJS.register(
  ArcElement,
  LineElement,
  PointElement,
  BarElement,
  CategoryScale,
  LinearScale,
  Filler,
  Tooltip,
  Legend,
  Title,
);

export { ChartJS };
