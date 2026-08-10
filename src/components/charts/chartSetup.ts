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

/** CSS 변수에서 차트 색을 읽어온다 — 팔레트 변경 시 style.css 만 고치면 된다 */
export function chartColor(n: 1 | 2 | 3 | 4 | 5): string {
  return getComputedStyle(document.documentElement)
    .getPropertyValue(`--chart-${n}`).trim();
}
export const CHART_SERIES = [1, 2, 3, 4, 5].map((n) => chartColor(n as 1));
export const chartAlpha = (hex: string, a = 0.15) => `${hex}${Math.round(a * 255).toString(16).padStart(2, '0')}`;
