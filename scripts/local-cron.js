#!/usr/bin/env node

const fetch = require('node-fetch')
const cron = require('node-cron')
const fs = require('fs')
const path = require('path')

// Configuration
const BASE_URL = process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'
const CRON_SECRET = process.env.CRON_SECRET || 'poofthemagicdragonsuperlong420stringdotcomokaybigdad'

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

async function triggerCronJob(endpoint, name) {
  try {
    log(`Triggering ${name}...`, 'cyan')
    
    const response = await fetch(`${BASE_URL}${endpoint}`, {
      method: 'POST',
      headers: {
        'x-cron': CRON_SECRET,
        'Content-Type': 'application/json'
      }
    })
    
    if (response.ok) {
      const result = await response.json()
      log(`✅ ${name} completed successfully`, 'green')
      if (result.universesProcessed) {
        log(`   Processed ${result.universesProcessed} universes`, 'blue')
      }
      if (result.playersUpdated) {
        log(`   Updated ${result.playersUpdated} players`, 'blue')
      }
      if (result.errors && result.errors.length > 0) {
        log(`   Errors: ${result.errors.join(', ')}`, 'yellow')
      }
    } else {
      const error = await response.json()
      log(`❌ ${name} failed: ${error.error || 'Unknown error'}`, 'red')
    }
  } catch (error) {
    log(`❌ ${name} error: ${error.message}`, 'red')
  }
}

async function testCronEndpoint() {
  try {
    log('Testing cron endpoint...', 'cyan')
    
    const response = await fetch(`${BASE_URL}/api/cron/test`, {
      method: 'POST',
      headers: {
        'x-cron': CRON_SECRET
      }
    })
    
    if (response.ok) {
      const result = await response.json()
      log('✅ Cron endpoint is working', 'green')
      log(`   Environment: ${result.environment}`, 'blue')
    } else {
      const error = await response.json()
      log(`❌ Cron endpoint test failed: ${error.error}`, 'red')
    }
  } catch (error) {
    log(`❌ Cron endpoint test error: ${error.message}`, 'red')
  }
}

// Single-heartbeat schedule: call one endpoint every minute
let scheduledTask = null

function startCronJobs() {
  if (scheduledTask) {
    try { scheduledTask.stop(); scheduledTask.destroy && scheduledTask.destroy() } catch {}
  }

  log('🚀 Starting local cron heartbeat...', 'bright')
  log(`Base URL: ${BASE_URL}`, 'blue')
  log(`Cron Secret: ${CRON_SECRET}`, 'blue')

  // Test endpoint first
  testCronEndpoint()

  // Heartbeat – every minute
  scheduledTask = cron.schedule(`* * * * *`, () => {
    triggerCronJob('/api/cron/heartbeat', 'Heartbeat')
  })

  log('📅 Cron job scheduled:', 'green')
  log('   - Heartbeat: Every 1 minute', 'blue')
  log('', 'reset')
  log('Press Ctrl+C to stop the cron service', 'yellow')
}

// Handle graceful shutdown
process.on('SIGINT', () => {
  log('\n🛑 Stopping cron service...', 'yellow')
  process.exit(0)
})

// Start the cron service
startCronJobs()


