<script setup lang="ts">
import NotionIcon from './NotionIcon.vue';
import GmailIcon from './GmailIcon.vue';
import GoogleDriveIcon from './GoogleDriveIcon.vue';
import GoogleCalendarIcon from './GoogleCalendarIcon.vue';
import UpNoteIcon from './UpNoteIcon.vue';
import ObsidianIcon from './ObsidianIcon.vue';
import NaverBandIcon from './NaverBandIcon.vue';

defineProps<{
  source: string;
  size?: number | string;
}>();
</script>

<template>
  <NotionIcon          v-if="source === 'notion'"   :size="size" />
  <GmailIcon           v-else-if="source === 'gmail'"    :size="size" />
  <GoogleDriveIcon     v-else-if="source === 'drive'"    :size="size" />
  <GoogleCalendarIcon  v-else-if="source === 'calendar'" :size="size" />
  <UpNoteIcon          v-else-if="source === 'upnote'"   :size="size" />
  <ObsidianIcon        v-else-if="source === 'obsidian'" :size="size" />
  <NaverBandIcon       v-else-if="source === 'band'"     :size="size" />
</template>
