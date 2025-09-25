import { createClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!

// Client for server-side operations with service role
export const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

// Client for reading session from cookies
export const supabaseServer = createClient(supabaseUrl, supabaseAnonKey)

// Get current user from session
export async function getCurrentUser() {
  const { data: { user }, error } = await supabaseServer.auth.getUser()
  if (error || !user) {
    throw new Error('Unauthorized')
  }
  return user
}
