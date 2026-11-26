// Põe no index.html a versão (hash do conteúdo) de admin.css, reliability.js e admin.js,
// para o navegador baixar o arquivo novo assim que ele muda. Rodar antes de publicar: node tools/versao.cjs
const fs=require('fs'),path=require('path'),crypto=require('crypto');const root=path.join(__dirname,'..');
let html=fs.readFileSync(path.join(root,'index.html'),'utf8');
for(const f of ['admin.css','reliability.js','admin.js']){const v=crypto.createHash('sha1').update(fs.readFileSync(path.join(root,f))).digest('hex').slice(0,10);
 html=html.replace(new RegExp(`(href|src)="${f.replace('.','\\.')}(\\?v=[0-9a-f]+)?"`),`$1="${f}?v=${v}"`)}
fs.writeFileSync(path.join(root,'index.html'),html);console.log('versões atualizadas');
