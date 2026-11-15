// Import invoice records carried in a URL fragment. Fragments are not sent to hosting.
(async()=>{
if(!location.hash.startsWith('#invoice-import='))return;
const token=location.hash.slice('#invoice-import='.length);history.replaceState(null,'',location.pathname+location.search);
try{
if(token.length>100000)throw Error();
const bytes=Uint8Array.from(atob(token.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));
const stream=new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate'));
const payload=JSON.parse(await new Response(stream).text());
if(payload.version!==1||!Array.isArray(payload.invoices)||payload.invoices.length>100)throw Error();
const allowed=['صيانة','تركيب','قطع غيار'];
for(const x of payload.invoices){if(typeof x.id!=='string'||!x.id||typeof x.number!=='string'||typeof x.customer!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(x.date)||!Array.isArray(x.items)||!x.items.length||!(x.people===null&&x.beneficiariesUnknown||Number.isInteger(x.people)&&x.people>0)||!Number.isFinite(x.discount)||x.discount<0||!Number.isFinite(x.tax)||x.tax<0||x.tax>100||x.items.some(l=>typeof l.name!=='string'||!allowed.includes(l.type)||!Number.isFinite(l.qty)||l.qty<=0||!Number.isFinite(l.price)||l.price<0))throw Error();if(!Number.isFinite(totals(x).total)||x.discount>totals(x).sub)throw Error()}
const existing=new Set(data.invoices.map(x=>x.id));let added=0;
const previous=structuredClone(data.invoices);
for(const x of payload.invoices){if(existing.has(x.id)||data.invoices.some(y=>y.sourceDocument&&y.sourceDocument===x.sourceDocument))continue;data.invoices.push(x);existing.add(x.id);added++}
if(!persist()){data.invoices=previous;return}
refresh();page('invoices');toast(added?'تمت إضافة '+added+' فاتورة إلى السجل.':'هذه الفواتير موجودة في السجل مسبقًا.');
}catch{toast('تعذّر استيراد الفواتير من الرابط. افتح رابط الاستيراد في متصفح حديث.');}
})();
