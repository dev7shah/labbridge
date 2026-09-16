const fs = require('fs');
const html = fs.readFileSync('webapp/index.html', 'utf8');
fs.writeFileSync('worker/src/index_html.ts', `export const INDEX_HTML = ${JSON.stringify(html)};\n`);

const htmlPhone = fs.readFileSync('webapp/phone.html', 'utf8');
fs.writeFileSync('worker/src/phone_html.ts', `export const PHONE_HTML = ${JSON.stringify(htmlPhone)};\n`);
