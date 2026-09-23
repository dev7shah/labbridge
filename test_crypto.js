const crypto = require('crypto');

async function test() {
  const enc = new TextEncoder();
  const sessionId = "123456789012";
  
  // mock crypto.subtle using webcrypto
  const subtle = crypto.webcrypto.subtle;
  
  const baseKey = await subtle.importKey(
    'raw', enc.encode(sessionId), { name: 'HKDF' }, false, ['deriveKey']
  );
  const key = await subtle.deriveKey(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: enc.encode('doctransit-v2'),
      info: enc.encode('file-transfer')
    },
    baseKey,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt']
  );

  const chunkIndex = 0;
  const plaintext = new Uint8Array([1, 2, 3, 4, 5]);

  // encrypt
  const iv = new Uint8Array(12);
  crypto.webcrypto.getRandomValues(iv);
  const view = new DataView(iv.buffer);
  view.setUint32(8, chunkIndex, false);

  const ciphertext = await subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    plaintext.buffer
  );

  const combined = new Uint8Array(12 + ciphertext.byteLength);
  combined.set(iv, 0);
  combined.set(new Uint8Array(ciphertext), 12);
  
  // decrypt
  const iv2 = combined.slice(0, 12);
  const view2 = new DataView(iv2.buffer, iv2.byteOffset, iv2.byteLength);
  const extractedIndex = view2.getUint32(8, false);
  const ciphertext2 = combined.slice(12);
  
  try {
    const pt = await subtle.decrypt({ name: 'AES-GCM', iv: iv2 }, key, ciphertext2);
    console.log("Success!", extractedIndex, new Uint8Array(pt));
  } catch (e) {
    console.error("Decrypt failed:", e);
  }
}
test();
