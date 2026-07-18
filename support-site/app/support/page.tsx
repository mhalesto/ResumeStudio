import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = { title: "Support", description: "Help with ResumeStudio accounts, data, purchases, AI credits, and documents." };

export default function SupportPage() {
  return <main>
    <header className="site-header"><Link className="brand" href="/"><span className="brand-mark">CV</span><span>Resume<span className="accent">Studio</span></span></Link><nav><Link href="/support">Support</Link><Link href="/privacy">Privacy</Link></nav></header>
    <article className="document">
      <p className="eyebrow">OFFICIAL SUPPORT</p><h1>How can we help?</h1><p className="updated">Support for ResumeStudio on iPhone and iPad</p>
      <section><h2>Contact</h2><div className="support-options"><div className="support-option"><strong>Email support</strong><p>Support email will be published here before launch.</p></div><div className="support-option"><strong>What to include</strong><p>Your iOS version, device model, ResumeStudio version, and the steps that caused the problem. Never send passwords or full payment details.</p></div></div></section>
      <section id="account"><h2>Account and data</h2><h3>Reset a password</h3><p>Open Settings → Account and backup → Forgot password. ResumeStudio sends reset instructions through Firebase Authentication.</p><h3>Delete an account</h3><p>Open Settings → Account and backup → Delete account and data. You can separately delete your server account, on-device workspace, and iCloud archive. Account deletion does not cancel an App Store subscription.</p><h3>Offline access</h3><p>Documents, editing, preview, export, application tracking, and saved interview work remain available offline. AI, account changes, referrals, Review Rooms, and cloud synchronization need a connection.</p></section>
      <section id="purchases"><h2>Plans and purchases</h2><p>Purchases are processed by Apple. Open ResumeStudio Settings → Plans and purchases to restore purchases. Manage or cancel a subscription from your Apple Account subscription settings. ResumeStudio cannot view your card details.</p><div className="callout"><strong>Paid access while offline</strong><p>A previously verified subscription remains available offline only until its locally verified expiration date. Reconnect to refresh an entitlement.</p></div></section>
      <section><h2>Documents and sync</h2><p>ResumeStudio stores drafts on device by default. If iCloud sync is enabled, the workspace archive is stored in the user’s private iCloud container. Conflict protection creates a recovery snapshot before replacing either copy.</p></section>
      <section><h2>AI and Review Rooms</h2><p>AI actions are started explicitly and use a Firebase proxy. Contact details, references, photographs, and private source links are excluded from résumé-writing requests. Review Rooms deliberately upload the selected exported PDF; owners can revoke or delete the hosted room.</p></section>
    </article><footer><span>© 2026 Halalisani Mbanjwa</span><Link href="/privacy">Privacy Policy</Link></footer>
  </main>;
}
