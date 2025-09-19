#!/usr/bin/env node

const fetch = require('node-fetch')

// Configuration
const BASE_URL = process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'
const CRON_SECRET = process.env.CRON_SECRET || 'local-dev-secret'

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

async function testEndpoint(endpoint, name) {
  try {
    log(`Testing ${name}...`, 'cyan')
    
    const response = await fetch(`${BASE_URL}${endpoint}`, {
      method: 'POST',
      headers: {
        'x-cron': CRON_SECRET,
        'Content-Type': 'application/json'
      }
    })
    
    if (response.ok) {
      const result = await response.json()
      log(`✅ ${name} - SUCCESS`, 'green')
      console.log(JSON.stringify(result, null, 2))
    } else {
      const error = await response.json()
      log(`❌ ${name} - FAILED: ${error.error || 'Unknown error'}`, 'red')
    }
  } catch (error) {
    log(`❌ ${name} - ERROR: ${error.message}`, 'red')
  }
}

async function testAllEndpoints() {
  log('🧪 Testing all cron endpoints...', 'bright')
  log(`Base URL: ${BASE_URL}`, 'blue')
  log(`Cron Secret: ${CRON_SECRET}`, 'blue')
  log('', 'reset')
  
  // Test basic endpoint first
  await testEndpoint('/api/cron/test', 'Cron Test Endpoint')
  log('', 'reset')
  
  // Test turn generation
  await testEndpoint('/api/cron/turn-generation', 'Turn Generation')
  log('', 'reset')
  
  // Test cycle events
  await testEndpoint('/api/cron/cycle-events', 'Cycle Events')
  log('', 'reset')
  
  // Test update events
  await testEndpoint('/api/cron/update-events', 'Update Events')
  log('', 'reset')
  
  // Test manual trigger
  await testEndpoint('/api/cron/manual', 'Manual Trigger')
  log('', 'reset')
  
  log('🏁 All tests completed!', 'bright')
}

// Run the tests
testAllEndpoints().catch(console.error)


