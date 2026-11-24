// GitHub Pages nema preusmjeravanja: 404.html je kopija aplikacije, pa
// čiste adrese (/oglas/…) rade i kad se otvore izravno.
import { copyFileSync, writeFileSync } from 'node:fs';
copyFileSync('dist/index.html', 'dist/404.html');
const base = process.env.BASE_PATH ?? '/bot/';
writeFileSync('dist/robots.txt', `User-agent: *\nAllow: ${base}\nDisallow: ${base}poruke\nDisallow: ${base}admin\n`);
console.log('404.html i robots.txt spremni');
