const chunks = [
  0x78a3, 0x1359, 0x4dca, 0x75eb,
  0xd8ab, 0x4141, 0x0a4d, 0x0070,
  0xe898, 0x7779, 0x4079, 0x8cc7,
  0xfe73, 0x2b6f, 0x6cee, 0x5203
];

let D = 0n;
for (let i = 0; i < chunks.length; i++) {
  D += BigInt(chunks[i]) << BigInt(16 * i);
}

console.log('D:', D.toString());
console.log('Expected:', 3709570593466943934355208350002891965628272942361211330481961634710185295104n.toString());
console.log('Match:', D === 3709570593466943934355208350002891965628272942361211330481961634710185295104n);
