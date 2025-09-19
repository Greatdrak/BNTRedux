import { NextRequest, NextResponse } from 'next/server'

// GET /api/cron/test - Test endpoint to verify cron is working
export async function GET(request: NextRequest) {
  const cronSecret = process.env.CRON_SECRET
  const xCronHeader = request.headers.get('x-cron')
  const xVercelCronHeader = request.headers.get('x-vercel-cron')
  
  return NextResponse.json({
    timestamp: new Date().toISOString(),
    cronSecret: cronSecret ? 'Set' : 'Not set',
    xCronHeader: xCronHeader || 'Not present',
    xVercelCronHeader: xVercelCronHeader || 'Not present',
    environment: process.env.NODE_ENV,
    message: 'Cron test endpoint is working'
  })
}

// POST /api/cron/test - Test endpoint for cron jobs
export async function POST(request: NextRequest) {
  try {
    const cronSecret = process.env.CRON_SECRET
    const xCronHeader = request.headers.get('x-cron')
    const xVercelCronHeader = request.headers.get('x-vercel-cron')
    
    // Check authorization
    if (xVercelCronHeader) {
      // Vercel cron job
      console.log('Vercel cron job triggered')
    } else if (xCronHeader && cronSecret && xCronHeader === cronSecret) {
      // Custom cron with secret
      console.log('Custom cron job triggered')
    } else {
      return NextResponse.json(
        { error: 'Unauthorized' },
        { status: 401 }
      )
    }
    
    return NextResponse.json({
      ok: true,
      timestamp: new Date().toISOString(),
      message: 'Cron test successful',
      headers: {
        xCronHeader: xCronHeader || 'Not present',
        xVercelCronHeader: xVercelCronHeader || 'Not present'
      }
    })
    
  } catch (error) {
    console.error('Error in cron test:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}


