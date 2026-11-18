
const hd=document.getElementById('topo');
if(hd)addEventListener('scroll',()=>hd.classList.toggle('scrolled',scrollY>10),{passive:true});
const bg=document.querySelector('.burger'),mn=document.getElementById('menu');
if(bg)bg.addEventListener('click',()=>{const o=mn.classList.toggle('open');bg.setAttribute('aria-expanded',o)});
const mq=document.getElementById('marquee');
if(mq){const n=mq.children.length;mq.innerHTML+=mq.innerHTML;[...mq.children].forEach((p,i)=>{if(i>=n)p.setAttribute('aria-hidden','true')})}
// alternar mensal/anual (-5%)
document.querySelectorAll('[data-bill]').forEach(b=>b.addEventListener('click',()=>{
  const anual=b.dataset.bill==='a';
  document.querySelectorAll('[data-bill]').forEach(x=>x.classList.toggle('on',x===b));
  document.querySelectorAll('.val[data-m]').forEach(v=>{const m=+v.dataset.m;v.querySelector('span').textContent=(anual?Math.round(m*0.95):m).toLocaleString('pt-BR')});
  document.querySelectorAll('[data-per]').forEach(p=>p.textContent=anual?'por mês, no plano anual':'cobrança mensal');
}));
const io=new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target)}}),{threshold:.1});
document.querySelectorAll('.rv').forEach(el=>io.observe(el));
