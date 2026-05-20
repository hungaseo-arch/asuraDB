<script setup lang="ts">
import { Database, Key, Bell, Globe, ChevronRight } from 'lucide-vue-next';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import Badge from '@/components/ui/Badge.vue';
import Separator from '@/components/ui/Separator.vue';

interface SettingItem {
  label: string;
  value: string;
  status: 'connected' | 'active' | 'planned';
}

interface SettingSection {
  icon: typeof Database;
  title: string;
  items: SettingItem[];
}

const settingSections: SettingSection[] = [
  {
    icon: Database,
    title: '데이터 소스 연결',
    items: [
      { label: 'Notion API',         value: 'secret_****',          status: 'connected' },
      { label: 'UpNote (MD 폴더)',   value: '/vault/upnote',        status: 'connected' },
      { label: 'Gmail OAuth 2.0',    value: 'PKDB 라벨 필터',       status: 'connected' },
      { label: 'Google Drive API',   value: 'Drive v3 Webhook',     status: 'connected' },
      { label: 'Obsidian Vault',     value: '미연동 (Phase 5)',     status: 'planned' },
    ],
  },
  {
    icon: Key,
    title: 'API 키 관리',
    items: [
      { label: 'Supabase URL',       value: 'https://xxxx.supabase.co',    status: 'connected' },
      { label: 'Supabase Anon Key',  value: 'eyJ****',                     status: 'connected' },
      { label: 'Embedding Model',    value: 'MiniLM-L12-v2 (384dim)',      status: 'connected' },
    ],
  },
  {
    icon: Bell,
    title: '동기화 주기',
    items: [
      { label: 'Notion',        value: '30분 폴링',           status: 'active' },
      { label: 'Gmail',         value: '15분 폴링',           status: 'active' },
      { label: 'Google Drive',  value: 'Webhook (실시간)',    status: 'active' },
      { label: 'UpNote',        value: '파일 변경 즉시',       status: 'active' },
    ],
  },
  {
    icon: Globe,
    title: '검색 설정',
    items: [
      { label: '기본 검색 모드',          value: 'Hybrid (FTS + Vector)',  status: 'active' },
      { label: 'match_count 기본값',     value: '5개',                     status: 'active' },
      { label: 'Ollama 모델',              value: 'qwen3:8b',               status: 'active' },
      { label: 'Ollama Base URL',         value: 'http://localhost:11434',  status: 'active' },
    ],
  },
];

const statusMap: Record<SettingItem['status'], { label: string; cn: string }> = {
  connected: { label: '연결됨', cn: 'border-green-500/30 text-green-400 bg-green-400/5' },
  active:    { label: '활성',   cn: 'border-blue-500/30 text-blue-400 bg-blue-400/5' },
  planned:   { label: '예정',   cn: 'border-violet-500/30 text-violet-400 bg-violet-400/5' },
};
</script>

<template>
  <div
    v-motion
    :initial="{ opacity: 0, y: 16 }"
    :enter="{ opacity: 1, y: 0, transition: { duration: 320 } }"
    class="p-4 md:p-6 max-w-2xl mx-auto space-y-5"
  >
    <div>
      <h1 class="text-xl font-bold">설정</h1>
      <p class="text-sm text-muted-foreground mt-0.5">
        데이터 소스 연결 · API 키 · 동기화 주기 · 검색 설정
      </p>
    </div>

    <Card v-for="section in settingSections" :key="section.title" class="border-border/60">
      <CardHeader class="pb-2">
        <CardTitle class="text-sm font-semibold flex items-center gap-2">
          <component :is="section.icon" :size="14" class="text-primary" /> {{ section.title }}
        </CardTitle>
      </CardHeader>
      <CardContent class="space-y-0 p-0">
        <template v-for="(item, i) in section.items" :key="item.label">
          <Separator v-if="i > 0" class="border-border/30" />
          <div class="flex items-center gap-3 px-5 py-3 hover:bg-muted/20 transition-colors cursor-pointer group">
            <div class="flex-1 min-w-0">
              <div class="text-sm text-foreground">{{ item.label }}</div>
              <div class="text-xs text-muted-foreground font-mono mt-0.5">{{ item.value }}</div>
            </div>
            <Badge variant="outline" :class="`text-[9px] px-1.5 py-0 h-4 ${statusMap[item.status].cn}`">
              {{ statusMap[item.status].label }}
            </Badge>
            <ChevronRight
              :size="12"
              class="text-muted-foreground/40 group-hover:text-muted-foreground transition-colors"
            />
          </div>
        </template>
      </CardContent>
    </Card>

    <div class="text-center text-[11px] text-muted-foreground/40 pt-2">
      AsuraDB v2.0 · Supabase Hybrid Search + Ollama MCP Agent
    </div>
  </div>
</template>
