#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

const envContent = `# Local Development Environment Variables
# Copy this file to .env.local and fill in your values

# Supabase Configuration
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url_here
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key_here
SUPABASE_SERVICE_ROLE_KEY=your_supabase_service_role_key_here

# Cron Configuration
CRON_SECRET=local-dev-secret

# Site URL (for local development)
NEXT_PUBLIC_SITE_URL=http://localhost:3000
`

const envPath = path.join(process.cwd(), '.env.local')

if (fs.existsSync(envPath)) {
  console.log('✅ .env.local already exists')
} else {
  fs.writeFileSync(envPath, envContent)
  console.log('✅ Created .env.local template')
  console.log('📝 Please edit .env.local with your Supabase credentials')
}

console.log('')
console.log('🚀 To start local cron development:')
console.log('1. Start your Next.js app: npm run dev')
console.log('2. In another terminal: npm run cron')
console.log('3. Or use the batch file: scripts/start-cron.bat')


