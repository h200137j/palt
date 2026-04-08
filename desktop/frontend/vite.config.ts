import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  // When running under Wails, assets are served from the Go binary.
  // The base path must be '/' for the embedded server.
  base: '/',
  build: {
    // Output to dist/ — this is what Wails embeds via //go:embed all:frontend/dist
    outDir: 'dist',
    emptyOutDir: true,
  },
  server: {
    // Dev server port for standalone preview (outside Wails)
    port: 5173,
    strictPort: true,
  },
})
