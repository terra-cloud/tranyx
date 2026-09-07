import type { GoldieConfig } from "/Users/zeuscajurao/.nvm/versions/node/v22.18.0/lib/node_modules/goldie/dist/config.js";

const APP_ROOT = "/Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_mobile";

const config: GoldieConfig = {
  appRoot: APP_ROOT,
  // Release/production simulator build for iOS
  appPath: `${APP_ROOT}/build/ios/Debug-production-iphonesimulator/Runner.app`,
  bundleId: "com.terraph.tranyx",

  // Android build
  android: {
    appPath: `${APP_ROOT}/build/app/outputs/flutter-apk/app-production-release.apk`,
    applicationId: "com.terraph.tranyx",
  },

  devices: ["iphone-6.9", "pixel-10-pro"],
  locales: ["en-US"],
  appearance: "dark",

  frame: { variant: "17-pro-blue" },

  theme: {
    background: "linear-gradient(160deg, #18113C 0%, #0E0E10 55%, #05030A 100%)",
    headlineColor: "#FFFFFF",
    subheadColor: "#A1A1AA",
    fontFamily: '-apple-system, "SF Pro Display", system-ui, sans-serif',
    copyHeightRatio: 0.24,
    deviceWidthRatio: 0.84,
    template: "editorial",
    layout: "classic",
  },

  store: {
    name: "Tranyx",
    subtitle: { "en-US": "Work and Transit. One Platform." },
    developer: "Terra PH Inc.",
    category: "Productivity",
    rating: 4.9,
    ratingCount: "2.4K Ratings",
    ageRating: "4+",
    price: "Free",
    description: {
      "en-US":
        "Tranyx is the modern service bridging and logistics platform built for the Philippines. Seamlessly connect with verified independent professionals for on-demand tasks, book freight and transit rentals, and enjoy end-to-end security with smart QR verification and instant escrow payments.",
    },
  },

  scenes: [
    {
      kind: "screenshot",
      id: "welcome",
      flow: "store-01-welcome",
      headline: { "en-US": "Work & Transit, Reimagined" },
      subhead: { "en-US": "Connect with verified professionals and trusted transit on one platform." },
    },
    {
      kind: "screenshot",
      id: "services",
      flow: "store-02-services",
      headline: { "en-US": "On-Demand Local Services" },
      subhead: { "en-US": "Book repairs, moving, tutoring, and skilled labor in minutes." },
    },
    {
      kind: "screenshot",
      id: "transit",
      flow: "store-03-transit",
      headline: { "en-US": "Smart Transit & Logistics" },
      subhead: { "en-US": "Rent vehicles and move cargo with live route tracking." },
    },
    {
      kind: "screenshot",
      id: "escrow",
      flow: "store-04-escrow",
      headline: { "en-US": "Guaranteed Escrow Protection" },
      subhead: { "en-US": "Payments remain safely secured until completed and QR-verified." },
    },
    {
      kind: "screenshot",
      id: "wallet",
      flow: "store-05-wallet",
      headline: { "en-US": "Fast Hybrid Web3 Wallet" },
      subhead: { "en-US": "Support for GCash, Card, and Solana ($SOL) with instant rewards." },
    },

    {
      kind: "preview",
      id: "preview",
      segments: [
        { id: "welcome", flow: "store-preview-01-welcome" },
        { id: "services", flow: "store-preview-02-services" },
        { id: "transit", flow: "store-preview-03-transit" },
        { id: "wallet", flow: "store-preview-04-wallet", holdSeconds: 2 },
      ],
    },
  ],
};

export default config;
