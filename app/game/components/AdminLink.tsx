'use client'

import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase-client'
import { useRouter } from 'next/navigation'
import styles from '../page.module.css'

export default function AdminLink() {
  const [isAdmin, setIsAdmin] = useState<boolean>(false)
  const [checked, setChecked] = useState<boolean>(false)
  const router = useRouter()

  useEffect(() => {
    const check = async () => {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session?.access_token) { setChecked(true); return }
      try {
        const res = await fetch('/api/admin/check', { headers: { Authorization: `Bearer ${session.access_token}` } })
        const j = await res.json()
        setIsAdmin(!!j?.is_admin)
      } catch { setIsAdmin(false) }
      setChecked(true)
    }
    check()
  }, [])

  if (!checked || !isAdmin) return null

  return (
    <button className={styles.commandItem} onClick={() => router.push('/admin')}>⚙️ Admin</button>
  )
}


