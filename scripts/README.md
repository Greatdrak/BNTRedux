# Local Cron Development

This directory contains scripts for running cron jobs locally during development.

## Setup

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Set environment variables:**
   Create a `.env.local` file with:
   ```env
   CRON_SECRET=local-dev-secret
   NEXT_PUBLIC_SITE_URL=http://localhost:3000
   ```

## Usage

### Start Local Cron Service
```bash
npm run cron
```

This will start a local cron service that runs:
- **Turn Generation**: Every 3 minutes
- **Cycle Events**: Every 6 hours  
- **Update Events**: Every 15 minutes

### Test Cron Endpoints
```bash
npm run cron:test
```

This will test all cron endpoints once and show the results.

### Manual Testing
You can also manually trigger cron jobs using curl:

```bash
# Test endpoint
curl -X POST -H "x-cron: local-dev-secret" http://localhost:3000/api/cron/test

# Turn generation
curl -X POST -H "x-cron: local-dev-secret" http://localhost:3000/api/cron/turn-generation

# Cycle events
curl -X POST -H "x-cron: local-dev-secret" http://localhost:3000/api/cron/cycle-events

# Update events
curl -X POST -H "x-cron: local-dev-secret" http://localhost:3000/api/cron/update-events
```

## Development Workflow

1. **Start your Next.js app:**
   ```bash
   npm run dev
   ```

2. **In another terminal, start the cron service:**
   ```bash
   npm run cron
   ```

3. **Monitor the output** to see cron jobs running and their results.

## Stopping

Press `Ctrl+C` to stop the cron service gracefully.

## Troubleshooting

- **Connection refused**: Make sure your Next.js app is running on the correct port
- **Unauthorized errors**: Check that `CRON_SECRET` matches between the script and your environment
- **Database errors**: Ensure your Supabase connection is properly configured


