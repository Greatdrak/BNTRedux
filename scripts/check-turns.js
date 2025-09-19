#!/usr/bin/env node

const fetch = require('node-fetch')

// Configuration
const BASE_URL = process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'

// Colors for console output
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m'
}

function log(message, color = 'reset') {
  const timestamp = new Date().toISOString()
  console.log(`${colors[color]}[${timestamp}] ${message}${colors.reset}`)
}

async function checkTurns() {
  try {
    log('🔍 Checking player turn count...', 'cyan')
    log(`Base URL: ${BASE_URL}`, 'blue')
    
    // This will fail without auth, but shows if the endpoint is reachable
    const response = await fetch(`${BASE_URL}/api/me`)
    
    if (response.status === 401) {
      log('✅ API is running (401 Unauthorized is expected without auth)', 'green')
      log('📝 To check turns, you need to:', 'yellow')
      log('   1. Start Next.js app: npm run dev', 'blue')
      log('   2. Start cron service: npm run cron', 'blue')
      log('   3. Check turns in the game UI', 'blue')
    } else if (response.status === 200) {
      const data = await response.json()
      log('✅ API is running and accessible', 'green')
      if (data.player) {
        log(`   Player: ${data.player.handle}`, 'blue')
        log(`   Turns: ${data.player.turns}/${data.player.turn_cap}`, 'blue')
        log(`   Last turn: ${data.player.last_turn_ts}`, 'blue')
      }
    } else {
      log(`❌ Unexpected response: ${response.status}`, 'red')
    }
    
  } catch (error) {
    if (error.code === 'ECONNREFUSED') {
      log('❌ Next.js app is not running', 'red')
      log('📝 Start it with: npm run dev', 'yellow')
    } else {
      log(`❌ Error: ${error.message}`, 'red')
    }
  }
}

// Run the check
checkTurns().catch(console.error)


