// Componentes visuais compartilhados dos portais (referência Emerald24, cores da marca).
export type IconName = 'home' | 'list' | 'building' | 'plus' | 'chart' | 'users' | 'user' | 'image' | 'briefcase' | 'star' | 'inbox' | 'info';

const paths: Record<IconName, string> = {
 home: 'M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z',
 list: 'M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01',
 building: 'M4 21V5a1 1 0 0 1 1-1h9a1 1 0 0 1 1 1v16M15 9h4a1 1 0 0 1 1 1v11M8 8h3M8 12h3M8 16h3M3 21h18',
 plus: 'M12 5v14M5 12h14',
 chart: 'M4 20V10M10 20V4M16 20v-7M22 20H2',
 users: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75',
 user: 'M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8',
 image: 'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zM8.5 10a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3M21 15l-5-5L5 21',
 briefcase: 'M4 7h16a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1zM16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2',
 star: 'm12 3 2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3 6.5 20.2l1-6.2L3 9.6l6.2-.9z',
 inbox: 'M22 12h-6l-2 3h-4l-2-3H2M5.5 5h13L22 12v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-6z',
 info: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20M12 16v-4M12 8h.01',
};

export function Icon({ name }: { name: IconName }) {
 return <svg className="sys-icon" viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d={paths[name]} /></svg>;
}

export interface QuickAction { icon: IconName; label: string; hint?: string; badge?: number; onClick: () => void }

// Cartões de ação rápida: ícone em círculo verde e rótulo embaixo, como os atalhos da referência.
export function QuickActions({ items, label }: { items: QuickAction[]; label: string }) {
 return <nav className="sys-quick" aria-label={label}>{items.map(item => <button key={item.label} type="button" className="sys-quick-card" onClick={item.onClick}>
  <span className="sys-quick-icon"><Icon name={item.icon} />{item.badge ? <em className="sys-badge" aria-label={`${item.badge} pendentes`}>{item.badge}</em> : null}</span>
  <span className="sys-quick-label">{item.label}</span>{item.hint && <small>{item.hint}</small>}
 </button>)}</nav>;
}

export function initials(name: string) { return name.split(' ').filter(Boolean).map(part => part[0]).slice(0, 2).join('').toUpperCase(); }
