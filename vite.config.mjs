import { defineConfig } from 'vite';
import { fileURLToPath } from 'node:url';

// Além do app (index.html), as páginas da landing oficial são entradas do build: o formulário de contato delas usa o mesmo serviço do app.
const pages = ['index', 'inicio', 'empresa', 'parceiros', 'patrocinio', 'intelligence', '404'];

export default defineConfig({
  build: {
    rollupOptions: {
      input: Object.fromEntries(pages.map(page => [page, fileURLToPath(new URL(`./${page}.html`, import.meta.url))])),
    },
  },
});
