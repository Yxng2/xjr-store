// Fill these in from Supabase → Project Settings → API.
// The anon key is SAFE to expose publicly — RLS is what protects your data.
// NEVER put the service_role key here.
window.XJR_CONFIG = {
  SUPABASE_URL: 'https://YOUR-PROJECT.supabase.co',
  SUPABASE_ANON_KEY: 'YOUR-ANON-KEY',
  // WhatsApp fallback (DB store_settings value overrides this once seeded)
  WHATSAPP_NUMBER: '+2347015119367',
  // Custom design AI — leave AI_ENDPOINT blank to show "not configured" notice (Option 1b)
  AI_ENDPOINT: '' // e.g. https://YOUR-PROJECT.supabase.co/functions/v1/generate-design
};
