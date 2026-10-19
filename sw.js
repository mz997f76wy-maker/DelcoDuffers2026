/* Cache only the public app shell. Scores and account data use the app's own queue/cache. */
const CACHE='delco-duffers-shell-v1';
const ROOT=new URL('./',self.location.href);
const SHELL=new URL('index.html',ROOT).href;
const LOGO=new URL('IMG_5029.jpeg',ROOT).href;
async function storeShell(response){
if(!response.ok||!response.headers.get('content-type')?.includes('text/html'))throw Error('App page unavailable');
const cache=await caches.open(CACHE);await cache.put(SHELL,response.clone());return response;
}
self.addEventListener('install',event=>{
event.waitUntil((async()=>{
await storeShell(await fetch(SHELL,{cache:'reload',signal:AbortSignal.timeout(10000)}));
try{const logo=await fetch(LOGO,{signal:AbortSignal.timeout(3000)});if(logo.ok)await (await caches.open(CACHE)).put(LOGO,logo)}catch{}
await self.skipWaiting();
})());
});
self.addEventListener('activate',event=>{
event.waitUntil((async()=>{
for(const key of await caches.keys())if(key.startsWith('delco-duffers-shell-')&&key!==CACHE)await caches.delete(key);
await self.clients.claim();
})());
});
async function offlineShell(){
const cached=await (await caches.open(CACHE)).match(SHELL);
if(!cached)return new Response('Connect once to prepare Delco Duffers for offline use.',{status:503,headers:{'Content-Type':'text/plain'}});
const html=(await cached.text()).replace('<head>','<head><script>window.__duffersOfflineLaunch=true;<\/script>');
return new Response(html,{headers:{'Content-Type':'text/html; charset=utf-8'}});
}
self.addEventListener('fetch',event=>{
const request=event.request,url=new URL(request.url);
if(request.method!=='GET'||url.origin!==ROOT.origin)return;
if(request.mode==='navigate'&&(url.pathname===ROOT.pathname||url.pathname===new URL(SHELL).pathname)){
const network=fetch(request).then(storeShell);
event.waitUntil(network.catch(()=>{}));
event.respondWith((async()=>{
let timer;
try{return await Promise.race([network,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('No signal')),2000)})])}
catch{return offlineShell()}
finally{clearTimeout(timer)}
})());
}else if(url.href===LOGO){
event.respondWith((async()=>{const cache=await caches.open(CACHE),saved=await cache.match(LOGO);return saved||fetch(request)})());
}
});
