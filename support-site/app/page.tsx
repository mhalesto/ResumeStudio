import Link from "next/link";

export default function Home() {
  return (
    <main>
      <header className="site-header">
        <Link className="brand" href="/" aria-label="ResumeStudio support home">
          <span className="brand-mark">CV</span><span>Resume<span className="accent">Studio</span></span>
        </Link>
        <nav aria-label="Support navigation">
          <Link href="/support">Support</Link><Link href="/privacy">Privacy</Link>
        </nav>
      </header>
      <section className="hero">
        <p className="eyebrow">RESUMESTUDIO HELP</p>
        <h1>Your career workspace,<br /><em>under your control.</em></h1>
        <p className="lede">Find help with your résumé, application workspace, purchases, privacy, account, and data.</p>
        <div className="hero-actions"><Link className="button primary" href="/support">Get support</Link><Link className="button" href="/privacy">Read the privacy policy</Link></div>
      </section>
      <section className="card-grid" aria-label="Help topics">
        <Link className="feature-card" href="/support#account"><span>01</span><h2>Account & data</h2><p>Password reset, account deletion, iCloud, and offline access.</p></Link>
        <Link className="feature-card" href="/support#purchases"><span>02</span><h2>Plans & purchases</h2><p>AI credits, template access, restoration, and subscriptions.</p></Link>
        <Link className="feature-card" href="/privacy"><span>03</span><h2>Privacy by design</h2><p>What stays on your device, what is sent, and how to erase it.</p></Link>
      </section>
      <footer><span>© 2026 Halalisani Mbanjwa</span><span>ResumeStudio for iPhone and iPad</span></footer>
    </main>
  );
}
