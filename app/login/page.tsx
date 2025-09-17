'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { supabase } from '@/lib/supabase-client'
import styles from './page.module.css'

export default function Login() {
  const [email, setEmail] = useState('')
  const [loading, setLoading] = useState(false)
  const [message, setMessage] = useState('')
  const [mode, setMode] = useState<'login' | 'register'>('login')
  const router = useRouter()

  useEffect(() => {
    // Check if user is already logged in
    const checkSession = async () => {
      const { data: { session } } = await supabase.auth.getSession()
      if (session) {
        // User is already logged in, redirect to home page
        router.push('/')
      }
    }
    
    checkSession()
  }, [router])


  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setMessage('')

    const { data, error } = await supabase.auth.signInWithOtp({
      email,
      options: {
        emailRedirectTo: `${window.location.origin}/`,
      },
    })

    console.log('Login OTP result:', { data, error })

    if (error) {
      setMessage(error.message)
    } else {
      setMessage('Check your email for the login link!')
    }

    setLoading(false)
  }

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setMessage('')

    try {
      // Sign up the user
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email,
        password: Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2), // Random password
        options: {
          emailRedirectTo: `${window.location.origin}/`,
        },
      })

      console.log('Signup result:', { authData, authError })

      if (authError) {
        setMessage(authError.message)
        setLoading(false)
        return
      }

      if (authData.user) {
        setMessage('Account created! Check your email to verify and start playing!')
      }
    } catch (error) {
      setMessage('Registration failed. Please try again.')
      console.error('Registration error:', error)
    }

    setLoading(false)
  }

  return (
    <div className={styles.container}>
      <div className={styles.card}>
        <h1 className={styles.title}>BNT Redux</h1>
        <p className={styles.subtitle}>Space Trading Game</p>
        
        <div className={styles.tabs}>
          <button 
            className={`${styles.tab} ${mode === 'login' ? styles.active : ''}`}
            onClick={() => setMode('login')}
          >
            Login
          </button>
          <button 
            className={`${styles.tab} ${mode === 'register' ? styles.active : ''}`}
            onClick={() => setMode('register')}
          >
            Register
          </button>
        </div>

        <form onSubmit={mode === 'login' ? handleLogin : handleRegister} className={styles.form}>
          <input
            type="email"
            placeholder="Enter your email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className={styles.input}
            required
          />
          
          <button 
            type="submit" 
            disabled={loading}
            className={styles.button}
          >
            {loading 
              ? (mode === 'login' ? 'Sending...' : 'Creating...') 
              : (mode === 'login' ? 'Send Magic Link' : 'Create Account')
            }
          </button>
        </form>

        {message && (
          <p className={styles.message}>{message}</p>
        )}
      </div>
    </div>
  )
}
