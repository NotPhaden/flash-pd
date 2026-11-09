import type { Config } from "tailwindcss";
const config: Config = {
  content: ["./app/**/*.{js,ts,jsx,tsx}", "./components/**/*.{js,ts,jsx,tsx}"],
  theme: { extend: { colors: { ink: "#0b0e13", panel: "#151a21", line: "#29313b", muted: "#8993a0", accent: "#4da3ff" } } },
  plugins: []
};
export default config;
