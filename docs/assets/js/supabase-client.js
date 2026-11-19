docs/supabase/migrations/0001_init.sq // Loads Supabase from CDN and exposes window.sb
(function () {
  const s = document.createElement('script');
  s.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
  s.onload = () => {
    const { createClient } = window.supabase;
    const cfg = window.XJR_CONFIG;
    if (!cfg.SUPABASE_URL.includes('YOUR-PROJECT')) {
      window.sb = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
        auth: { persistSession: true, autoRefreshToken: true }
      });
    } else {
      console.warn('[XJR] Supabase not configured. Edit assets/js/config.js');
    }
    document.dispatchEvent(new Event('sb-ready'));
  };
  document.head.appendChild(s);
})();
