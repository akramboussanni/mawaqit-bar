import assert from 'node:assert/strict';
import {kimonoLink} from '../kimono.js';

const link = 'https://kimono.example/api/v1/prayer/feed/abc_DEF-123';
assert.equal(kimonoLink(`  ${link}\n`), link, 'A pasted link');
assert.equal(kimonoLink(`mawaqit-kimono://connect?link=${encodeURIComponent(link)}`), link, 'The connect address');
assert.equal(kimonoLink(`${link}?q=paris`), link, 'A query is dropped');
assert.equal(kimonoLink('https://kimono.example/prayer'), null, 'Another Kimono page');
assert.equal(kimonoLink('ftp://kimono.example/api/v1/prayer/feed/abc'), null, 'Another scheme');
assert.equal(kimonoLink(`mawaqit-kimono://other?link=${encodeURIComponent(link)}`), null, 'Another action');
assert.equal(kimonoLink('Paris'), null, 'Words');
console.log('Kimono tests passed');
