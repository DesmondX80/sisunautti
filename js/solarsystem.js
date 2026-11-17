// Aurinkokunnan kartan pohja: planeetat kiertoradoillaan oikeassa mittakaavassa, ylhäältä ekliptikan pohjoispuolelta
// katsottuna. Kevätpisteen suunta on oikealle. Lentokartta (voyage.js) piirtää aluksen ja reitin tämän päälle.
import { num } from './core.js';
import { AU_KM, SUN_RADIUS_KM, orbitPoint } from './planets.js';

// Mittakaavajanalle pyöreä pituus, joka on enintään annettu määrä astronomisia yksiköitä.
const AU_STEPS=[20,10,5,2,1,0.5,0.2,0.1,0.05,0.02,0.01];
const KM_STEPS=[1e6,5e5,2e5,1e5,5e4,2e4,1e4,5000,2000,1000];
function scaleStep(maxAu) {
  const au=AU_STEPS.find(v=>v<=maxAu);
  if(au) return [au, `${num(au,2)} AU`];
  const km=KM_STEPS.find(v=>v<=maxAu*AU_KM) ?? 1000;
  return [km/AU_KM, `${num(km)} km`];
}

/**
 * Kiertorata murtoviivana. Radan 720 perusvälistä piirretään vain kartalle osuvat, ja ne jaetaan muutaman
 * pikselin paloihin, jotta rata pysyy tarkkana myös lähelle zoomattuna eikä planeetta irtoa viivasta.
 */
function orbitPath(ctx, el, toPx, w, h) {
  const N=720, step=2*Math.PI/N, margin=20;
  let prev=toPx(orbitPoint(el,0)), pen=false;
  for(let i=1;i<=N;i++) {
    const p=toPx(orbitPoint(el,i*step));
    const off=Math.max(prev[0],p[0])<-margin || Math.min(prev[0],p[0])>w+margin || Math.max(prev[1],p[1])<-margin || Math.min(prev[1],p[1])>h+margin;
    if(off) {pen=false; prev=p; continue;}
    if(!pen) {ctx.moveTo(prev[0],prev[1]); pen=true;}
    const parts=Math.min(4000,Math.ceil(Math.hypot(p[0]-prev[0],p[1]-prev[1])/3));
    for(let j=1;j<parts;j++) {const q=toPx(orbitPoint(el,(i-1+j/parts)*step)); ctx.lineTo(q[0],q[1]);}
    ctx.lineTo(p[0],p[1]);
    prev=p;
  }
}

/**
 * Aurinkokunnan perusnäkymä kankaalle: tausta, kiertoradat, Aurinko ja planeetat nimineen sekä mittakaavajana.
 * toPx muuntaa ekliptikan koordinaatit (AU) pikseleiksi ja k on pikseliä per AU. Palauttaa kohteiden
 * napautusalueet.
 */
export function drawScene(ctx, planets, toPx, w, h, k, selected = null) {
  ctx.fillStyle='#03050b'; ctx.fillRect(0,0,w,h);

  for(const p of planets) {
    ctx.beginPath(); orbitPath(ctx,p.el,toPx,w,h);
    ctx.strokeStyle=p.color; ctx.globalAlpha=p.name===selected ? 0.8 : 0.35; ctx.lineWidth=p.name===selected ? 1.5 : 1; ctx.stroke();
  }
  ctx.globalAlpha=1;

  // Kohteet piirretään todellisen kokoisina, mutta vähintään pisteenä, jotta ne näkyvät kaukaa.
  const bodies=[{name:'Aurinko', color:'#ffd75e', pos:[0,0,0], radiusKm:SUN_RADIUS_KM, min:5}, ...planets.map(p=>({...p, min:3.5}))];
  const hits=[];
  for(const b of bodies) {
    const [x,y]=toPx(b.pos), r=Math.max(b.min,b.radiusKm/AU_KM*k);
    hits.push({name:b.name, x, y, r});
    if(x<-r||x>w+r||y<-r||y>h+r) continue;
    if(b.name==='Aurinko') {
      const glow=ctx.createRadialGradient(x,y,r*0.5,x,y,r*3);
      glow.addColorStop(0,'rgba(255,215,94,.35)'); glow.addColorStop(1,'rgba(255,215,94,0)');
      ctx.fillStyle=glow; ctx.beginPath(); ctx.arc(x,y,r*3,0,2*Math.PI); ctx.fill();
    }
    ctx.beginPath(); ctx.arc(x,y,r,0,2*Math.PI); ctx.fillStyle=b.color; ctx.fill();
    if(b.name===selected) {ctx.beginPath(); ctx.arc(x,y,r+5,0,2*Math.PI); ctx.strokeStyle='#fff'; ctx.lineWidth=1.5; ctx.stroke();}
  }

  // Nimet: valittu ja Maa ensin, eikä päällekkäisiä piirretä (koko aurinkokunnan näkymässä sisäplaneetat ovat lähekkäin).
  ctx.font='11px system-ui, sans-serif'; ctx.textAlign='center'; ctx.lineJoin='round';
  const order=[...hits].sort((a,b)=>(b.name===selected)-(a.name===selected) || (b.name==='Maa')-(a.name==='Maa'));
  const taken=[];
  for(const hit of order) {
    if(hit.x<0||hit.x>w||hit.y<0||hit.y>h) continue;
    // Reunan lähellä nimi siirretään kokonaan kartalle.
    const tw=ctx.measureText(hit.name).width, x=Math.max(tw/2+4,Math.min(w-tw/2-4,hit.x)), y=hit.y-hit.r-6;
    const box=[x-tw/2-2,y-11,x+tw/2+2,y+3];
    if(box[2]<0||box[0]>w||box[3]<0||box[1]>h) continue;
    if(taken.some(t=>box[0]<t[2]&&box[2]>t[0]&&box[1]<t[3]&&box[3]>t[1])) continue;
    taken.push(box);
    ctx.lineWidth=3; ctx.strokeStyle='#03050b'; ctx.strokeText(hit.name,x,y);
    ctx.fillStyle=hit.name===selected ? '#fff' : '#c9d3ec'; ctx.fillText(hit.name,x,y);
  }

  const [au,text]=scaleStep(w/4/k), len=au*k;
  ctx.beginPath(); ctx.moveTo(10,h-14); ctx.lineTo(10,h-10); ctx.lineTo(10+len,h-10); ctx.lineTo(10+len,h-14);
  ctx.strokeStyle='#8b9ac0'; ctx.lineWidth=1; ctx.stroke();
  ctx.fillStyle='#8b9ac0'; ctx.fillText(text,10+len/2,h-16);
  ctx.textAlign='right'; ctx.fillText('kevätpiste →',w-8,18);
  return hits;
}
