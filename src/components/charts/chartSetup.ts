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

/** 임의의 CSS 변수 값을 읽어온다 — 토큰이 아닌 raw hex 문자열이 필요한 곳(SVG fill, 알파 합성)에 쓴다 */
export function cssVar(name: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

/** CSS 변수에서 차트 색을 읽어온다 — 팔레트 변경 시 style.css 만 고치면 된다 */
export function chartColor(n: 1 | 2 | 3 | 4 | 5): string {
  return cssVar(`--chart-${n}`);
}
export const CHART_SERIES = [1, 2, 3, 4, 5].map((n) => chartColor(n as 1));
export const chartAlpha = (hex: string, a = 0.15) => `${hex}${Math.round(a * 255).toString(16).padStart(2, '0')}`;

function scaleLightness(hex: string, factor: number): string {
  const r = parseInt(hex.slice(1, 3), 16) / 255;
  const g = parseInt(hex.slice(3, 5), 16) / 255;
  const b = parseInt(hex.slice(5, 7), 16) / 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  let h = 0, s = 0;
  const l = (max + min) / 2;
  const d = max - min;
  if (d !== 0) {
    s = d / (1 - Math.abs(2 * l - 1));
    switch (max) {
      case r: h = ((g - b) / d) % 6; break;
      case g: h = (b - r) / d + 2; break;
      default: h = (r - g) / d + 4;
    }
    h *= 60;
    if (h < 0) h += 360;
  }
  const l2 = Math.min(1, Math.max(0, l * factor));
  const c = (1 - Math.abs(2 * l2 - 1)) * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = l2 - c / 2;
  let [r2, g2, b2] = [0, 0, 0];
  if (h < 60) [r2, g2, b2] = [c, x, 0];
  else if (h < 120) [r2, g2, b2] = [x, c, 0];
  else if (h < 180) [r2, g2, b2] = [0, c, x];
  else if (h < 240) [r2, g2, b2] = [0, x, c];
  else if (h < 300) [r2, g2, b2] = [x, 0, c];
  else [r2, g2, b2] = [c, 0, x];
  const toHex = (v: number) => Math.round((v + m) * 255).toString(16).padStart(2, '0');
  return `#${toHex(r2)}${toHex(g2)}${toHex(b2)}`;
}

/**
 * chart-1~5를 명도 100%/75%/50% 3단계로 확장해 최대 15색을 만든다.
 * 시리즈 수가 5색으로 부족한 화면(카테고리 legend 등)에서 쓴다.
 */
export function chartSeriesPalette(count = 15): string[] {
  const tiers = [1, 0.75, 0.5];
  const out: string[] = [];
  outer: for (const tier of tiers) {
    for (const base of CHART_SERIES) {
      out.push(tier === 1 ? base : scaleLightness(base, tier));
      if (out.length >= count) break outer;
    }
  }
  return out;
}
