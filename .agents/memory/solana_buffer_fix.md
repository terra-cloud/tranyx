# Solana Browser Integration & Memory Fixes

## 1. Buffer is not defined (Pay with SOL & USDT)

### The Bug
When using `@solana/web3.js` in a browser environment via script tags, transaction construction and encoding methods (such as `SystemProgram.transfer` or SPL Token transfers) utilize Node.js `Buffer` primitives internally for layout encoding. If `Buffer` is not globally defined in the browser window/global runtime, the library crashes with:
`ReferenceError: Buffer is not defined`

### The Solution
1. **Load a valid, browserified local Buffer asset**: Standard CDN files can be CommonJS bundles containing `require()` which crash in client runtimes. We download a pre-packaged browser UMD bundle locally to `web/buffer.min.js` and serve it directly.
2. **Bind the constructor globally**: Run an inline script block **immediately after** the Buffer script and **before** the `@solana/web3.js` library is loaded:
   ```html
   <!-- Load Buffer polyfill locally -->
   <script src="/buffer.min.js"></script>
   <script>
     try {
       window.Buffer = window.Buffer || window.buffer?.Buffer;
       if (window.Buffer) {
         window.globalThis = window.globalThis || window;
         window.globalThis.Buffer = window.Buffer;
         console.log("Buffer polyfill successfully initialized on globalThis. Type:", typeof window.Buffer);
       } else {
         console.error("Buffer polyfill could not be resolved from local script!");
       }
     } catch (e) {
       console.error("Buffer polyfill error:", e);
     }
   </script>
   <!-- Load Solana web3.js -->
   <script src="https://cdn.jsdelivr.net/npm/@solana/web3.js@1.95.3/lib/index.iife.min.js"></script>
   ```

---

## 2. transferInstruction is not defined (USDT Payment)

### The Bug
In the SPL Token transfer workflow, when checking if a recipient's Associated Token Account (ATA) exists, we execute:
```javascript
if (!toATAInfo) {
  const createATAInstruction = ...
  transaction.add(createATAInstruction);
}
```
If the instruction variable is declared inside the conditional block, it creates block-scoping issues. When the recipient *already has* a token account (`toATAInfo` is truthy), the block that defines the transfer instruction is skipped, causing:
`ReferenceError: transferInstruction is not defined`

### The Solution
1. Define the SPL Token `transferInstruction` **globally/outside** the conditional blocks of the Associated Token Account (ATA) existence check.
2. Append the ATA creation instruction to the transaction *first* (if the account does not exist), and then append the `transferInstruction` afterwards.
3. Example correct layout:
   ```javascript
   const transferInstruction = new solanaWeb3.TransactionInstruction({
     keys: keys,
     programId: TOKEN_PROGRAM_ID,
     data: data,
   });

   const transaction = new solanaWeb3.Transaction();
   if (!toATAInfo) {
     const createATAInstruction = new solanaWeb3.TransactionInstruction({ ... });
     transaction.add(createATAInstruction);
   }
   transaction.add(transferInstruction);
   ```

---

## 3. Environment-Based RPC Mappings

Always resolve the Solana RPC endpoints and USDT mints based on the environment instead of hardcoding Mainnet:
- **dev**: Solana Devnet (`https://api.devnet.solana.com`)
- **uat**: Solana Devnet (`https://api.devnet.solana.com`)
- **prod**: Solana Mainnet (`https://rpc.ankr.com/solana`)

Ensure fallback RPCs in `index.html` parse `window.location.hostname` to choose the correct default network if no explicit `rpcUrl` is passed from Dart.
