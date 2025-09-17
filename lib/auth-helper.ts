import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from './supabase-server'

export interface AuthResult {
  userId: string
}

export interface AuthError {
  error: {
    code: string
    message: string
  }
}

export async function verifyBearerToken(request: NextRequest): Promise<AuthResult | AuthError> {
  try {
    // Extract Authorization header
    const authHeader = request.headers.get('authorization')
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return {
        error: {
          code: 'unauthorized',
          message: 'Missing or invalid bearer token'
        }
      }
    }
    
    // Extract token
    const token = authHeader.substring(7) // Remove 'Bearer ' prefix
    
    if (!token) {
      return {
        error: {
          code: 'unauthorized',
          message: 'Missing or invalid bearer token'
        }
      }
    }
    
    // Verify token with Supabase admin client
    const { data: { user }, error } = await supabaseAdmin.auth.getUser(token)
    
    if (error || !user) {
      return {
        error: {
          code: 'unauthorized',
          message: 'Invalid or expired token'
        }
      }
    }
    
    return { userId: user.id }
    
  } catch (error) {
    console.error('Auth verification error:', error)
    return {
      error: {
        code: 'unauthorized',
        message: 'Authentication failed'
      }
    }
  }
}

export function createAuthErrorResponse(error: AuthError, status: number = 401): NextResponse {
  return NextResponse.json(error, { status })
}
