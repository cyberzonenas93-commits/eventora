import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes('node_modules')) return undefined
          if (id.includes('/firebase/') || id.includes('@firebase')) {
            return 'vendor-firebase'
          }
          if (id.includes('/react') || id.includes('/react-dom') || id.includes('/react-router')) {
            return 'vendor-react'
          }
          if (id.includes('/recharts/') || id.includes('/d3-')) {
            return 'vendor-charts'
          }
          if (id.includes('/lucide-react/')) {
            return 'vendor-icons'
          }
          if (id.includes('/pdfjs-dist/')) {
            return 'vendor-pdf'
          }
          if (id.includes('/tesseract.js/') || id.includes('/tesseract.js-core/')) {
            return 'vendor-ocr'
          }
          if (id.includes('/xlsx/')) {
            return 'vendor-xlsx'
          }
          return 'vendor'
        },
      },
    },
  },
})
