import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  // AsuraDB 메인앱과 같은 GitHub Pages 에 하위 경로로 얹는다.
  //   메인앱 https://hungaseo-arch.github.io/asuraDB/
  //   이 앱   https://hungaseo-arch.github.io/asuraDB/pwa/
  // 바꾸면 public/manifest.json 의 scope 도 같이 바꿔야 한다.
  base: '/asuraDB/pwa/',
  plugins: [
    vue(),
    VitePWA({
      registerType: 'autoUpdate',
      manifest: false,
      workbox: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg}'],
      },
    }),
  ],
  resolve: {
    alias: { '@': '/src' },
  },
});
