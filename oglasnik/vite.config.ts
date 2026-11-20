import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';

// BASE: putanja na kojoj se stranica poslužuje (GitHub Pages: /bot/, Vercel: /).
export default defineConfig({
  base: process.env.BASE_PATH ?? '/bot/',
  plugins: [preact()],
  build: { target: 'es2020', sourcemap: false },
  test: { environment: 'node' },
});
