import { createClient } from '@supabase/supabase-js';

const SB_URL = import.meta.env.VITE_SB_URL as string;
const SB_KEY = import.meta.env.VITE_SB_KEY as string;

export const supabase = createClient(SB_URL, SB_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
});

export async function sbHeaders(): Promise<Record<string, string>> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token ?? SB_KEY;
  return { apikey: SB_KEY, Authorization: `Bearer ${token}` };
}
