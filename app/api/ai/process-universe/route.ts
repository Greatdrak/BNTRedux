import { NextRequest, NextResponse } from 'next/server'
import { AIService } from '@/lib/ai-service'

export async function POST(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const universeId = searchParams.get('universeId')
    
    if (!universeId) {
      return NextResponse.json({
        success: false,
        error: 'Universe ID is required'
      }, { status: 400 })
    }
    
    const aiService = new AIService()
    const result = await aiService.processUniverse(universeId)
    
    return NextResponse.json(result)
    
  } catch (error) {
    console.error('AI processing error:', error)
    return NextResponse.json({
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    }, { status: 500 })
  }
}
