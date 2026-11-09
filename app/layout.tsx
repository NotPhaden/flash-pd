import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Centrală | Police Department",
  description: "Platformă de management pentru departamentul de poliție.",
  icons: { icon: "/favicon.png", shortcut: "/favicon.png", apple: "/favicon.png" }
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ro"><body>{children}</body></html>;
}
