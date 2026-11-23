import { defineConfig } from 'vite';

// Uma entrada só (index.html): a landing oficial é React dentro do app (src/landing-site) e os caminhos
// /empresa, /parceiros etc. caem no index.html (fallback do Vite no dev; rewrite do vercel.json em produção).
export default defineConfig({});