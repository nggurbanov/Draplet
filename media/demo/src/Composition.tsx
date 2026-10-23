import React from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';

type Props = {accent: string};
const ease = Easing.bezier(0.2, 0.8, 0.2, 1);
const ramp = (t: number, a: number, b: number) => interpolate(t, [a, b], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease});
const hold = (t: number, a: number, b: number, c: number, d: number) => ramp(t,a,b)*(1-ramp(t,c,d));
const lerp = (a: number,b: number,p: number) => a+(b-a)*p;

type GlyphName = 'cloud'|'star'|'headphones'|'gauge'|'bolt'|'gear'|'moon'|'wifi'|'battery';
const Glyph = ({name,x,y,color='#FAF8F4',size=25}:{name:GlyphName;x:number;y:number;color?:string;size?:number}) => <g transform={`translate(${x-size/2} ${y-size/2}) scale(${size/24})`} stroke={color} fill="none" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
  {name==='cloud' && <path d="M6.3 18H18a4 4 0 0 0 .5-8 6.2 6.2 0 0 0-11.9-1.5A4.8 4.8 0 0 0 6.3 18Z"/>}
  {name==='star' && <path d="m12 2.8 2.8 5.7 6.3.9-4.6 4.5 1.1 6.3-5.6-3-5.6 3 1.1-6.3L3 9.4l6.2-.9Z" fill={color} strokeWidth="1.1"/>}
  {name==='headphones' && <><path d="M4 14V11a8 8 0 0 1 16 0v3"/><rect x="3" y="12" width="4" height="8" rx="2"/><rect x="17" y="12" width="4" height="8" rx="2"/></>}
  {name==='gauge' && <><path d="M4.2 18a9 9 0 1 1 15.6 0Z"/><path d="m12 13 4-5"/><circle cx="12" cy="13" r="1" fill={color}/></>}
  {name==='bolt' && <path d="m13 2-9 12h7l-1 8 10-13h-7Z"/>}
  {name==='gear' && <><circle cx="12" cy="12" r="7.3"/><circle cx="12" cy="12" r="2.6"/>{[0,45,90,135].map(a=><path key={a} d="M12 2v3M12 19v3" transform={`rotate(${a} 12 12)`}/>)}</>}
  {name==='moon' && <path d="M20 15.8A9 9 0 0 1 8.2 4a9 9 0 1 0 11.8 11.8Z"/>}
  {name==='wifi' && <><path d="M2 8.5a16 16 0 0 1 20 0M5.5 12a10 10 0 0 1 13 0M9 15.5a4.7 4.7 0 0 1 6 0"/><circle cx="12" cy="19" r="1" fill={color} stroke="none"/></>}
  {name==='battery' && <><rect x="1.5" y="6.5" width="19" height="11" rx="3"/><path d="M23 10v4"/><rect x="4" y="9" width="12" height="6" rx="1" fill={color} stroke="none"/></>}
</g>;
const Chevron=({x,y,angle=0}:{x:number;y:number;angle?:number})=><path d="m-4-8 8 8-8 8" transform={`translate(${x} ${y}) rotate(${angle})`} stroke="#FAF8F4" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" fill="none"/>;

// The pointer, UI and glyphs are all authored vectors. Nothing is screen-captured.
export const DrapletDemo: React.FC<Props> = ({accent}) => {
 const frame=useCurrentFrame(); const {fps}=useVideoConfig(); const t=frame/fps;
 const left=hold(t,1.6,1.95,3.1,3.45);
 const right=hold(t,4.5,4.9,15.25,15.65);
 const pinned=hold(t,7.45,7.75,13.25,13.55);
 const pocketX=930+42*pinned;
 const popup=hold(t,8.55,8.8,13.45,13.65);
 const target=hold(t,6.12,6.32,7.65,7.85);
 const inDrag=t>=6.02&&t<7.45;const outDrag=t>=10.9&&t<13.25;
 const cmd=hold(t,5.75,5.9,7.55,7.8)+hold(t,10.5,10.65,13.35,13.6);
 const cursorVisible=hold(t,.3,.65,16.2,16.6);
 const keyframes:[number,number,number][]=[
  [0,700,400],[.7,700,400],[1.45,248,98],[2.25,248,98],[2.95,626,98],
  [3.55,626,98],[4.35,1140,98],[5.05,1140,98],[5.65,1014,98],
  [6.02,1014,98],[7.2,1014,243],[7.85,1014,243],[8.45,972,98],
  [9.05,972,98],[10.4,924,241],[10.9,924,241],[13.1,1014,98],
  [13.8,1014,98],[15.1,1140,98],[15.7,1140,98],[16.4,700,400],[18,700,400],
 ];
 const seg=keyframes.findIndex((v,i)=>i<keyframes.length-1&&t>=v[0]&&t<keyframes[i+1][0]);
 const i=Math.max(0,seg);const a=keyframes[i];const b=keyframes[i+1];const p=ramp(t,a[0],b[0]);
 const cx=lerp(a[1],b[1],p),cy=lerp(a[2],b[2],p);
 const pulses=[1.58,3.08,4.48,8.53,15.23];
 const pulse=Math.max(0,...pulses.map(at=>hold(t,at,at+.05,at+.12,at+.3)));
 const panelLeft=pocketX-90;
 return <AbsoluteFill style={{backgroundColor:'#EFE9E0',fontFamily:'-apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif'}}>
 <svg viewBox="0 0 1440 600" width="100%" height="100%" aria-label="Schematic Draplet demonstration: reveal menus, pin a status icon in Pocket and return it with Command-drag">
 <defs>
  <clipPath id="screen"><rect x="56" y="72" width="1328" height="454" rx="18"/></clipPath>
  <clipPath id="left-menus"><rect x="264" y="72" width={340*left} height="52"/></clipPath>
  <clipPath id="right-icons"><rect x={1140-236*right} y="72" width={236*right} height="52"/></clipPath>
  <filter id="screen-shadow" x="-10%" y="-20%" width="120%" height="150%"><feDropShadow dx="0" dy="12" stdDeviation="15" floodColor="#302218" floodOpacity=".12"/></filter>
  <filter id="panel-shadow" x="-30%" y="-30%" width="160%" height="180%"><feDropShadow dx="0" dy="9" stdDeviation="9" floodColor="#221C16" floodOpacity=".22"/></filter>
  <filter id="pointer-shadow" x="-100%" y="-100%" width="300%" height="300%"><feDropShadow dx="0" dy="2" stdDeviation="2" floodOpacity=".22"/></filter>
 </defs>
 <rect x="56" y="72" width="1328" height="454" rx="18" fill="#CBBDAA" filter="url(#screen-shadow)"/>
 <g clipPath="url(#screen)">
  <rect x="56" y="72" width="1328" height="454" fill="#D8CCBC"/>
  <path d="M56 458C360 290 570 500 940 372s390-162 444-124v278H56Z" fill="#C5B49D"/>
  <path d="M705 526c205-180 495-111 679-209v209Z" fill="#B7A087"/>
  <g>
   <rect x="100" y="198" width="664" height="370" rx="13" fill="#FAF7F1"/>
   <path d="M113 198h638a13 13 0 0 1 13 13v38H100v-38a13 13 0 0 1 13-13Z" fill="#F1ECE4"/>
   <path d="M100 249h664" stroke="#E1D9CE"/>
   <circle cx="122" cy="224" r="6" fill="#ED7064"/><circle cx="143" cy="224" r="6" fill="#E7BB57"/><circle cx="164" cy="224" r="6" fill="#86B484"/>
   <text x="432" y="231" textAnchor="middle" fill="#81786D" fontSize="17" fontWeight="500">Untitled</text>
   <path d="M142 307h229M142 339h458M142 371h414M142 403h437" stroke="#E8E1D6" strokeWidth="7" strokeLinecap="round"/>
  </g>
  <rect x="56" y="72" width="1328" height="52" fill="#262522"/>
  <path d="M650 72h140v18a13 13 0 0 1-13 13H663a13 13 0 0 1-13-13Z" fill="#131311"/>
  <g fill="#FAF8F4">
   <path d="M99 85c2-3 5-4 7-4 0 3-1 6-4 7-1 1-2 1-3 1-1-1-1-2 0-4Zm10 16c1 0 2-1 3-2-1 4-4 10-7 10-2 0-3-1-5-1s-3 1-5 1c-4-1-7-8-7-13 0-5 3-8 7-8 2 0 4 2 6 2 1 0 4-2 6-2 2 0 5 2 6 4-4 2-5 7-4 9Z"/>
   <text x="134" y="106" fontSize="23" fontWeight="650">Notes</text>
  </g>
  <g clipPath="url(#left-menus)" fill="#FAF8F4" fontSize="21" fontWeight="450">
   <text x="270" y="106">File</text><text x="324" y="106">Edit</text><text x="381" y="106">View</text><text x="454" y="106">Window</text><text x="551" y="106">Help</text>
  </g>
  <Chevron x={248+378*left} y={98} angle={180*left}/>
  <g clipPath="url(#right-icons)">
   <Chevron x={pocketX} y={98} angle={90+180*popup}/>
   <Glyph name="cloud" x={972+42*pinned} y={98}/>
   <g opacity={t>=6.02&&t<13.25?0:1-pinned}><Glyph name="star" x={1014} y={98} color={accent}/></g>
   <Glyph name="headphones" x={1056} y={98}/><Glyph name="gauge" x={1098} y={98}/>
  </g>
  <Chevron x={1140} y={98} angle={180*(1-right)}/>
  <Glyph name="wifi" x={1200} y={98} size={26}/><Glyph name="battery" x={1245} y={98} size={28}/>
  <text x="1326" y="106" textAnchor="middle" fill="#FAF8F4" fontSize="21" fontWeight="500">9:41</text>
  {outDrag&&<path d="M994 84v28" stroke={accent} strokeWidth="3" strokeLinecap="round"/>}
 </g>
 <g opacity={target} transform={`translate(1014 155) translate(0 ${(1-target)*-5})`} filter="url(#panel-shadow)">
  <path d="m-12 0 8-8q4-4 8 0l8 8h67a15 15 0 0 1 15 15v105a15 15 0 0 1-15 15H-79a15 15 0 0 1-15-15V15A15 15 0 0 1-79 0Z" fill="#F5EEE4"/>
  <rect x="-82" y="12" width="164" height="108" rx="9" fill="none" stroke="#B75D37" strokeWidth="1.5" strokeDasharray="5 5"/>
  <text x="0" y="42" textAnchor="middle" fill="#71543F" fontSize="15" fontWeight="550">Keep Star in Pocket</text>
  <path d="M-15 63v28h30V63M-22 63h44" stroke="#B75D37" strokeWidth="1.5" fill="none"/>
 </g>
 <g opacity={popup} transform={`translate(${panelLeft} ${149+(1-popup)*-6})`} filter="url(#panel-shadow)">
  <path d="M0 16A16 16 0 0 1 16 0h62l8-8q4-4 8 0l8 8h62a16 16 0 0 1 16 16v112a16 16 0 0 1-16 16H16a16 16 0 0 1-16-16Z" fill="#383630"/>
  <Glyph name="bolt" x={42} y={44} color="#EFE9E0"/><Glyph name="gear" x={90} y={44} color="#EFE9E0"/><Glyph name="moon" x={138} y={44} color="#EFE9E0"/>
  <g opacity={outDrag?0:pinned}><Glyph name="star" x={42} y={92} color={accent}/></g>
 </g>
 <g opacity={cursorVisible}>
  {(inDrag||outDrag)&&<g filter="url(#pointer-shadow)"><Glyph name="star" x={cx-5} y={cy-7} color={accent} size={28}/></g>}
  <g transform={`translate(${cx} ${cy})`}>
   {pulse>0&&<circle r={10+10*pulse} fill="none" stroke="#BA7958" strokeWidth="1.7" opacity={.6*pulse}/>}
   <path d="M0 0v25l6.2-6.8 5.2 11 4.7-2.3-5.3-10.6 9.1-.4Z" fill="#24231F" stroke="#FFFFFF" strokeWidth="1.5" strokeLinejoin="round" filter="url(#pointer-shadow)"/>
   <g opacity={Math.min(cmd,1)} transform="translate(24 25)"><rect width="37" height="34" rx="7" fill="#FAF7F1" stroke="#C9BBAC"/><text x="18.5" y="24" textAnchor="middle" fontSize="25" fill="#4D443A">⌘</text></g>
  </g>
 </g>
 </svg>
 </AbsoluteFill>;
};
