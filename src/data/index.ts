export type SourceType = 'notion' | 'upnote' | 'gmail' | 'drive' | 'calendar' | 'obsidian' | 'band';

export interface SearchResult {
  id: string;
  source: SourceType;
  title: string;
  content: string;
  sourceUrl: string;
  tags: string[];
  date: string;
  vectorScore: number;
  ftsScore: number;
  rrfScore: number;
  chunkType: 'section' | 'paragraph';
}

export interface SourceStat {
  source: SourceType;
  label: string;
  count: number;
  lastSync: string;
  status: 'synced' | 'syncing' | 'error' | 'planned';
  color: string;
  icon: string;
}

export interface RecentActivity {
  id: string;
  type: 'search' | 'sync' | 'agent';
  source?: SourceType;
  query?: string;
  message: string;
  time: string;
}

export interface KpiItem {
  label: string;
  value: string;
  delta: string;
  deltaDir: 'up' | 'down';
}

export interface RoadmapPhase {
  phase: number;
  title: string;
  duration: string;
  status: 'completed' | 'in-progress' | 'pending' | 'planned';
  items: string[];
}

// ─── Source Stats ────────────────────────────────────────────────────────────
export const sourceStats: SourceStat[] = [
  { source: 'notion',   label: 'Notion',       count: 1_847, lastSync: '5분 전',  status: 'synced',  color: '#ffffff', icon: 'notion' },
  { source: 'upnote',   label: 'UpNote',       count: 923,   lastSync: '12분 전', status: 'synced',  color: '#4ade80', icon: 'upnote' },
  { source: 'gmail',    label: 'Gmail',        count: 412,   lastSync: '8분 전',  status: 'synced',  color: '#f87171', icon: 'gmail' },
  { source: 'drive',    label: 'Google Drive', count: 301,   lastSync: '20분 전', status: 'syncing', color: '#60a5fa', icon: 'drive' },
  { source: 'obsidian', label: 'Obsidian',     count: 0,     lastSync: '—',      status: 'planned', color: '#a78bfa', icon: 'obsidian' },
];

export const totalDocs = sourceStats.reduce((sum, s) => sum + s.count, 0);

// ─── Dashboard KPI ───────────────────────────────────────────────────────────
export const kpiData: KpiItem[] = [
  { label: '총 문서 청크', value: '3,483', delta: '+127',  deltaDir: 'up' },
  { label: '오늘 검색',    value: '42',    delta: '+8',    deltaDir: 'up' },
  { label: '평균 응답',    value: '1.2s',  delta: '-0.3s', deltaDir: 'up' },
  { label: 'Agent 호출',  value: '9',     delta: '+3',    deltaDir: 'up' },
];

// ─── Search Volume Chart ─────────────────────────────────────────────────────
export const searchVolumeData = [
  { date: '05/11', notion: 18, upnote: 9,  gmail: 5,  drive: 3 },
  { date: '05/12', notion: 22, upnote: 11, gmail: 7,  drive: 4 },
  { date: '05/13', notion: 15, upnote: 14, gmail: 3,  drive: 6 },
  { date: '05/14', notion: 28, upnote: 8,  gmail: 9,  drive: 2 },
  { date: '05/15', notion: 34, upnote: 19, gmail: 11, drive: 8 },
  { date: '05/16', notion: 29, upnote: 15, gmail: 8,  drive: 5 },
  { date: '05/17', notion: 42, upnote: 21, gmail: 12, drive: 7 },
];

// ─── Source Distribution Pie ─────────────────────────────────────────────────
export const sourceDistribution = [
  { name: 'Notion',       value: 1847, fill: 'var(--color-chart-1)' },
  { name: 'UpNote',       value: 923,  fill: 'var(--color-chart-2)' },
  { name: 'Gmail',        value: 412,  fill: 'var(--color-chart-3)' },
  { name: 'Google Drive', value: 301,  fill: 'var(--color-chart-4)' },
];

// ─── Recent Activity ─────────────────────────────────────────────────────────
export const recentActivity: RecentActivity[] = [
  { id: '1', type: 'search', source: 'notion', query: '프로젝트 진행 현황 2026', message: '"프로젝트 진행 현황 2026" 검색 — 5개 결과', time: '2분 전' },
  { id: '2', type: 'sync',   source: 'gmail',  message: 'Gmail PKDB 라벨 42건 동기화 완료', time: '8분 전' },
  { id: '3', type: 'agent',  message: 'Agent: "4월 AGR 마진 분석" 도구 3회 호출', time: '15분 전' },
  { id: '4', type: 'search', source: 'upnote', query: '인도네시아 세관 규정', message: '"인도네시아 세관 규정" 검색 — 3개 결과', time: '22분 전' },
  { id: '5', type: 'sync',   source: 'drive',  message: 'Google Drive 웹훅 트리거 — 3건 업데이트', time: '31분 전' },
  { id: '6', type: 'search', source: 'gmail',  query: '공급사 협상', message: '"공급사 협상" 이메일 검색 — 8개 스레드', time: '45분 전' },
];

// ─── Roadmap Phases ──────────────────────────────────────────────────────────
export const roadmapPhases: RoadmapPhase[] = [
  {
    phase: 1, title: '기반 마이그레이션', duration: '2~3주', status: 'completed',
    items: [
      'Supabase 스키마/인덱스/함수 적용',
      'ChromaDB → pgvector 마이그레이션',
      'Vue 3 + Tailwind 프로젝트 초기화',
      'UpNote / Notion / Drive 수집기 전환',
      'Hybrid Search 함수 전환',
    ],
  },
  {
    phase: 2, title: 'Ingestion Pipeline 고도화', duration: '1~2주', status: 'in-progress',
    items: [
      'Markdown Parser + Chunker 구현',
      'Metadata Extractor (소스별)',
      'Link Analysis (Notion relation, 스레드)',
      'content_hash 변경 감지',
      '기존 데이터 재처리',
    ],
  },
  {
    phase: 3, title: 'Gmail 연동', duration: '1~2주', status: 'in-progress',
    items: [
      'Gmail OAuth 인증 흐름',
      'gmail_collector.py (PKDB 라벨)',
      'draft_email MCP 도구 연결',
      'Vue: Gmail 소스 필터 + 초안 UI',
    ],
  },
  {
    phase: 4, title: 'MCP Agent + 대시보드', duration: '3~4주', status: 'pending',
    items: [
      'MCP Agent 실행 루프',
      '5개 MCP 도구 구현 및 테스트',
      '타이어 판매 데이터 입력/차트',
      '브랜드별/지점별 마진 분석',
      '모바일 반응형 최적화',
    ],
  },
  {
    phase: 5, title: 'Obsidian 연동 + 고도화', duration: '향후', status: 'planned',
    items: [
      'Obsidian Vault 수집기 (wikilink, frontmatter)',
      'Drive Webhook + Gmail Pub/Sub 실시간 동기화',
      'PWA: 오프라인 검색 캐시',
      '다국어 UI (한국어/인도네시아어)',
      '개인화 검색 가중치',
    ],
  },
];
