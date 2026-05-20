import { ref, computed, type Ref } from 'vue';

type SortMode = 'rrf' | 'date_desc' | 'date_asc';

export function useSortMode<T extends { date: string }>(items: Ref<T[]>) {
  const sortMode = ref<SortMode>('rrf');

  function cycleSortMode() {
    if (sortMode.value === 'rrf')            sortMode.value = 'date_desc';
    else if (sortMode.value === 'date_desc') sortMode.value = 'date_asc';
    else                                     sortMode.value = 'rrf';
  }

  const sortLabel = computed(() => ({
    rrf: '관련도순', date_desc: '최신순', date_asc: '오래된순',
  }[sortMode.value]));

  const sorted = computed(() => {
    if (sortMode.value === 'rrf') return items.value;
    return [...items.value].sort((a, b) => {
      const da = a.date || '', db = b.date || '';
      return sortMode.value === 'date_desc' ? db.localeCompare(da) : da.localeCompare(db);
    });
  });

  return { sortMode, cycleSortMode, sortLabel, sorted };
}
