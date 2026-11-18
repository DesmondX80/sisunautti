// Jaetut apufunktiot.
export const el = id => document.getElementById(id);
export const num = (v, digits=0) => v.toLocaleString('fi-FI', {maximumFractionDigits:digits});
// Pelin tila ja asetukset tallentuvat tämän selaimen localStorageen.
export const saved = {
  get(key, fallback) {try {return JSON.parse(localStorage.getItem(key)) ?? fallback;} catch(e) {return fallback;}},
  set(key, value) {try {localStorage.setItem(key, JSON.stringify(value));} catch(e) {console.warn('Tallennus epäonnistui');}},
};
export function button(className, text, onClick) {
  const b=document.createElement('button'); b.type='button'; b.className=className; b.textContent=text;
  b.addEventListener('click',onClick); return b;
}
