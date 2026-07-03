import{m as l}from"./index-DkhpgpvV.js";/**
 * @license lucide-vue-next v0.462.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const p=l("DownloadIcon",[["path",{d:"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4",key:"ih7n3h"}],["polyline",{points:"7 10 12 15 17 10",key:"2ggqvy"}],["line",{x1:"12",x2:"12",y1:"15",y2:"3",key:"1vk2je"}]]);function i(e){if(e==null)return"";const n=String(e);return/[",\n]/.test(n)?`"${n.replace(/"/g,'""')}"`:n}function u(e,n,c){const s=[n,...c].map(a=>a.map(i).join(",")),r=new Blob(["\uFEFF"+s.join(`\r
`)],{type:"text/csv;charset=utf-8;"}),t=URL.createObjectURL(r),o=document.createElement("a");o.href=t,o.download=e.endsWith(".csv")?e:`${e}.csv`,document.body.appendChild(o),o.click(),o.remove(),URL.revokeObjectURL(t)}export{p as D,u as e};
