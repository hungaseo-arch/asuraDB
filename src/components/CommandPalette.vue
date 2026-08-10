<script setup lang="ts">
import { ref, computed, watch, onMounted, onUnmounted, nextTick } from 'vue';
import { useRouter } from 'vue-router';
import { Search, ArrowRight, CornerDownLeft, Clock } from 'lucide-vue-next';
import { getRecent } from '@/lib/recent';

interface NavItem { to?: string; href?: string; icon: unknown; label: string }
const props = defineProps<{ items: NavItem[] }>();

const router = useRouter();
const open = ref(false);
const query = ref('');
const active = ref(0);
const inputRef = ref<HTMLInputElement | null>(null);
const recent = ref<{ path: string; label: string }[]>([]);

type Cmd = { kind: 'search' | 'nav'; label: string; icon?: unknown; group?: string; run: () => void };

function navCmd(it: NavItem, group: string): Cmd {
  return {
    kind: 'nav', label: it.label, icon: it.icon, group,
    run: () => (it.href ? window.open(it.href, '_blank', 'noopener') : go({ path: it.to ?? '/' })),
  };
}

const commands = computed<Cmd[]>(() => {
  const q = query.value.trim();
  if (!q) {
    const list: Cmd[] = [];
    for (const r of recent.value) {
      const it = props.items.find(i => i.to === r.path);
      if (it) list.push(navCmd(it, '최근'));
    }
    for (const it of props.items) list.push(navCmd(it, '바로가기'));
    return list;
  }
  const ql = q.toLowerCase();
  const list: Cmd[] = [{ kind: 'search', label: `전체 검색: “${q}”`, run: () => go({ path: '/search', query: { q } }) }];
  for (const it of props.items) if (it.label.toLowerCase().includes(ql)) list.push(navCmd(it, '바로가기'));
  return list;
});

function go(loc: Parameters<typeof router.push>[0]) { router.push(loc); close(); }

function openPalette() {
  open.value = true; query.value = ''; active.value = 0;
  recent.value = getRecent();
  nextTick(() => inputRef.value?.focus());
}
function close() { open.value = false; }

watch(query, () => { active.value = 0; });

function onKeydown(e: KeyboardEvent) {
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
    e.preventDefault();
    open.value ? close() : openPalette();
    return;
  }
  if (!open.value) return;
  if (e.key === 'Escape') { e.preventDefault(); close(); }
  else if (e.key === 'ArrowDown') { e.preventDefault(); active.value = Math.min(active.value + 1, commands.value.length - 1); }
  else if (e.key === 'ArrowUp') { e.preventDefault(); active.value = Math.max(active.value - 1, 0); }
  else if (e.key === 'Enter') { e.preventDefault(); commands.value[active.value]?.run(); }
}

function onExternalOpen() { openPalette(); }

onMounted(() => {
  window.addEventListener('keydown', onKeydown);
  window.addEventListener('asura:open-command', onExternalOpen);
});
onUnmounted(() => {
  window.removeEventListener('keydown', onKeydown);
  window.removeEventListener('asura:open-command', onExternalOpen);
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-9999 flex items-start justify-center bg-black/40 backdrop-blur-sm pt-[12vh] px-4"
      @click.self="close"
    >
      <div class="w-full max-w-lg rounded-2xl border border-border bg-card shadow-2xl overflow-hidden">
        <!-- 입력 -->
        <div class="flex items-center gap-2.5 px-4 border-b border-border">
          <Search :size="18" class="text-muted-foreground shrink-0" />
          <input
            ref="inputRef"
            v-model="query"
            type="text"
            placeholder="페이지 이동 또는 자료 검색…"
            class="flex-1 bg-transparent py-3.5 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none"
          />
          <kbd class="text-[10px] text-muted-foreground border border-border rounded px-1.5 py-0.5 shrink-0">ESC</kbd>
        </div>

        <!-- 결과 -->
        <ul v-if="commands.length" class="max-h-80 overflow-y-auto py-1.5">
          <template v-for="(c, i) in commands" :key="i">
            <li v-if="c.group && c.group !== commands[i - 1]?.group"
                class="px-4 pt-2 pb-1 text-[10px] uppercase tracking-wider text-muted-foreground/60 font-semibold flex items-center gap-1">
              <Clock v-if="c.group === '최근'" :size="10" />{{ c.group }}
            </li>
          <li>
            <!-- 선택 행은 '강조(10% 녹색)'가 아니라 '주요 요소(30% 파랑)'다.
                 hover 는 secondary — accent 가 primary-soft 와 같은 값이라
                 hover 와 선택 상태가 구분되지 않는다. -->
            <button
              type="button"
              class="w-full flex items-center gap-3 px-4 py-2.5 text-left transition-colors"
              :class="i === active ? 'bg-primary-soft text-primary-soft-foreground' : 'text-foreground hover:bg-secondary'"
              @mouseenter="active = i"
              @click="c.run()"
            >
              <component :is="c.kind === 'search' ? Search : c.icon" :size="16" class="shrink-0"
                :class="i === active ? 'text-primary' : 'text-muted-foreground'" />
              <span class="flex-1 text-sm truncate">{{ c.label }}</span>
              <CornerDownLeft v-if="i === active" :size="13" class="text-muted-foreground shrink-0" />
              <ArrowRight v-else-if="c.kind === 'search'" :size="13" class="text-muted-foreground/50 shrink-0" />
            </button>
          </li>
          </template>
        </ul>
        <div v-else class="px-4 py-8 text-center text-sm text-muted-foreground">결과 없음</div>

        <!-- 하단 힌트 -->
        <div class="flex items-center gap-3 px-4 py-2 border-t border-border text-[10px] text-muted-foreground bg-muted/30">
          <span><kbd class="border border-border rounded px-1">↑</kbd><kbd class="border border-border rounded px-1 ml-0.5">↓</kbd> 이동</span>
          <span><kbd class="border border-border rounded px-1">↵</kbd> 선택</span>
          <span class="ml-auto">⌘K · Ctrl K 로 열기/닫기</span>
        </div>
      </div>
    </div>
  </Teleport>
</template>
