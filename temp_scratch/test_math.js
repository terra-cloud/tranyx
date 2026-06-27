const { PublicKey } = require('@solana/web3.js');

const address = "EYC8SkTpSMeeu9Lf9Xm6KNwH2WE1PTMJhZKT81DF9MoD";
const bytes = new PublicKey(address).toBytes();

console.log('Bytes:', Array.from(bytes));

const p = (1n << 255n) - 19n;
let y = 0n;
for (let i = 0; i < 32; i++) {
  y += BigInt(bytes[i]) << BigInt(8 * i);
}

const x0 = (y >> 255n) & 1n;
y = y & ((1n << 255n) - 1n);

console.log('y < p:', y < p);
console.log('y:', y.toString());

const d = 37095705934669439343138083508754565189542113879843219016388785533085940283555n;
const y2 = (y * y) % p;
const u = (y2 - 1n + p) % p;
const v = (d * y2 + 1n) % p;

// Fermat's Little Theorem for modular inverse of v mod p
function modPow(base, exponent, modulus) {
  if (modulus === 1n) return 0n;
  let result = 1n;
  base = base % modulus;
  while (exponent > 0n) {
    if (exponent % 2n === 1n) {
      result = (result * base) % modulus;
    }
    exponent = exponent >> 1n;
    base = (base * base) % modulus;
  }
  return result;
}

const vInv = modPow(v, p - 2n, p);
const x2 = (u * vInv) % p;

if (x2 === 0n) {
  console.log('x2 is 0, u is:', u);
} else {
  const eulerLimit = (p - 1n) >> 1n;
  const val = modPow(x2, eulerLimit, p);
  console.log('val:', val.toString());
  console.log('is on curve:', val === 1n);
}
