# Performance Optimization Plan

## Current Issues Identified

### 1. Excessive API Calls in Game UI
**Problem**: Every player action triggers `mutatePlayer()` and `mutateSector()` which refetch ALL data from the API.

**Locations**:
- After move: Lines 363-364
- After trade: Lines 402-403  
- After hyperspace: Line 439
- After claim planet: Lines 494-495
- After store resource: Line 529
- After withdraw resource: Line 560
- After upgrade: Line 589
- After auto-trade: Line 621
- After warp scan: Line 656
- Manual refresh: Lines 662-663
- After trade route execution: Line 713
- After travel confirmation: Lines 752-753
- After combat: Line 898
- After special port purchase: Line 1061
- Planet overlay refresh: Line 1085
- Trade route changes: Lines 1101-1103

**Impact**: 15+ full data refetches during normal gameplay, each hitting 2 API endpoints.

### 2. No Response Caching
**Problem**: API responses don't include updated data, requiring separate fetch calls.

**Solution**: Return updated player/sector data with action responses.

### 3. SWR Configuration Too Aggressive
**Problem**: Current `dedupingInterval: 10000` (10 seconds) is still short for a turn-based game.

**Solution**: Increase to 60000 (1 minute) and only invalidate on actual changes.

### 4. Multiple useEffect Triggers
**Problem**: Universe ID changes trigger multiple refetches (lines 278-284, 287-291).

**Solution**: Consolidate into single effect.

### 5. No Database Indexes on Critical Queries
**Problem**: Common queries may be doing full table scans.

**Critical indexes needed**:
- `players.user_id` (for /api/me lookups)
- `players.universe_id` (for universe player lists)
- `sectors.universe_id, sectors.number` (composite for sector lookups)
- `warps.from_sector` (for warp gate queries)
- `ports.sector_id` (for port lookups)
- `planets.sector_id` (for planet lookups)
- `trade_routes.player_id, trade_routes.is_active` (composite for active routes)
- `ai_action_log.player_id, ai_action_log.created_at` (for recent activity - now less critical with logging disabled)

### 6. RLS Policies May Be Inefficient
**Problem**: Row-level security checks on every query can be expensive.

**Solution**: Review and optimize RLS policies, ensure they use indexed columns.

## Implementation Plan

### Phase 1: Quick Wins (Immediate)
1. ✅ Disable AI logging
2. Return updated data with API responses
3. Increase SWR deduping interval
4. Consolidate useEffect triggers

### Phase 2: Database Optimization (Next)
5. Add critical indexes
6. Optimize RLS policies
7. Add query performance monitoring

### Phase 3: Advanced (Future)
8. Implement optimistic UI updates
9. Add Redis caching layer
10. Implement WebSocket for real-time updates

## Performance Targets

- **Page load**: < 2 seconds
- **Action response**: < 500ms
- **Data refresh**: < 300ms
- **Concurrent users supported**: 100+

## Monitoring

Track these metrics:
- Average API response time
- Number of API calls per user session
- Database query execution time
- Cache hit rate (once implemented)




