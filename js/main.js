// Sisunautti: käynnistys, Tietoa-ikkuna ja service worker.
import { el } from './core.js';
import { initVoyage } from './voyage.js';

initVoyage();

el('about-open').addEventListener('click',()=>el('about').showModal());
el('about-close').addEventListener('click',()=>el('about').close());
el('about').addEventListener('click',e=>{if(e.target===el('about')) el('about').close();});

if('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(()=>{});
