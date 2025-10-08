# API Reference Documentation

## Overview
This document provides a comprehensive reference for all API endpoints in the BNT Redux application.

## Authentication
All API endpoints require authentication via Bearer token in the Authorization header:
```
Authorization: Bearer <access_token>
```

## Core Game APIs

### Player Management

#### `GET /api/me`
Get current player information and universe status.

**Response:**
```json
{
  "player": {
    "id": "uuid",
    "handle": "string",
    "universe_id": "uuid",
    "current_sector": "uuid",
    "turns": 1000,
    "turns_spent": 50
  },
  "universe": {
    "id": "uuid",
    "name": "string",
    "sector_count": 500
  },
  "ship": {
    "id": "uuid",
    "name": "string",
    "hull": 1,
    "hull_max": 150,
    "credits": 10000,
    "ore": 0,
    "organics": 0,
    "goods": 0,
    "energy": 0,
    "colonists": 0
  }
}
```

#### `POST /api/register`
Register a new player in a universe.

**Request Body:**
```json
{
  "universe_id": "uuid",
  "handle": "string"
}
```

**Response:**
```json
{
  "success": true,
  "player_id": "uuid",
  "ship_id": "uuid"
}
```

### Sector Information

#### `GET /api/sector`
Get detailed sector information including warps, ports, planets, and ships.

**Query Parameters:**
- `number` (integer): Sector number
- `universe_id` (uuid): Universe ID

**Response:**
```json
{
  "sector": {
    "number": 100,
    "ownerPlayerId": null,
    "controlled": false,
    "ownershipThreshold": 3,
    "name": null
  },
  "warps": [99, 101, 150, 200],
  "ships": [
    {
      "id": "uuid",
      "name": "Scout",
      "player": {
        "id": "uuid",
        "handle": "PlayerName",
        "is_ai": false
      }
    }
  ],
  "port": {
    "id": "uuid",
    "kind": "ore",
    "stock": {
      "ore": 1000000,
      "organics": 500000,
      "goods": 200000,
      "energy": 300000
    },
    "prices": {
      "ore": 15.00,
      "organics": 8.00,
      "goods": 22.00,
      "energy": 3.00
    }
  },
  "planets": [
    {
      "id": "uuid",
      "name": "Planet Name",
      "owner": false,
      "ownerName": null,
      "colonists": 10000,
      "colonistsMax": 50000,
      "stock": {
        "ore": 5000,
        "organics": 3000,
        "goods": 2000,
        "energy": 8000,
        "credits": 15000
      },
      "defenses": {
        "fighters": 100,
        "torpedoes": 50,
        "shields": 200
      },
      "base": {
        "built": false,
        "cost": 50000,
        "colonistsRequired": 10000,
        "resourcesRequired": 10000
      }
    }
  ]
}
```

#### `GET /api/map`
Get universe map data for navigation.

**Query Parameters:**
- `universe_id` (uuid): Universe ID

**Response:**
```json
{
  "sectors": [
    {
      "id": "uuid",
      "number": 100,
      "hasPort": true,
      "hasPlanets": true,
      "planetCount": 2,
      "owner": null
    }
  ]
}
```

### Ship Management

#### `GET /api/ship`
Get current ship information.

**Query Parameters:**
- `universe_id` (uuid): Universe ID

**Response:**
```json
{
  "id": "uuid",
  "name": "Scout",
  "hull": 1,
  "hull_max": 150,
  "computer": 1,
  "computer_max": 150,
  "power": 1,
  "power_max": 150,
  "armor_lvl": 1,
  "armor_max": 150,
  "shield_lvl": 1,
  "shields": 0,
  "energy": 100,
  "energy_max": 150,
  "beam_weapons": 1,
  "beam_weapons_max": 150,
  "torpedo_launchers": 1,
  "torpedo_launchers_max": 150,
  "credits": 10000,
  "ore": 0,
  "organics": 0,
  "goods": 0,
  "energy_cargo": 0,
  "colonists": 0,
  "fighters": 0,
  "torpedoes": 0
}
```

#### `GET /api/ship/capacity`
Get ship cargo capacity information.

**Query Parameters:**
- `universe_id` (uuid): Universe ID

**Response:**
```json
{
  "hull_capacity": 100,
  "cargo_used": 0,
  "cargo_free": 100,
  "energy_capacity": 150,
  "energy_used": 0,
  "energy_free": 150
}
```

#### `POST /api/ship/rename`
Rename the current ship.

**Request Body:**
```json
{
  "name": "New Ship Name"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Ship renamed successfully"
}
```

#### `POST /api/ship/upgrade`
Upgrade ship equipment.

**Request Body:**
```json
{
  "upgrade_type": "hull"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Hull upgraded to level 2",
  "new_level": 2,
  "cost": 2000
}
```

### Movement

#### `POST /api/move`
Move to a different sector.

**Request Body:**
```json
{
  "sector_number": 101,
  "universe_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Moved to sector 101",
  "turns_used": 1,
  "new_sector": 101
}
```

### Trading

#### `POST /api/trade`
Trade resources at a port.

**Request Body:**
```json
{
  "port_id": "uuid",
  "action": "buy",
  "resource": "ore",
  "qty": 100,
  "universe_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Bought 100 ore for 1500 credits",
  "total_cost": 1500,
  "new_credits": 8500,
  "new_cargo": {
    "ore": 100,
    "organics": 0,
    "goods": 0,
    "energy": 0
  }
}
```

#### `POST /api/trade/auto`
Execute automatic trading based on current cargo and port prices.

**Request Body:**
```json
{
  "port_id": "uuid",
  "universe_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "trades": [
    {
      "action": "sell",
      "resource": "ore",
      "qty": 50,
      "profit": 750
    }
  ],
  "total_profit": 750
}
```

### Planet Management

#### `GET /api/planet/list`
Get list of player's planets.

**Query Parameters:**
- `universe_id` (uuid): Universe ID

**Response:**
```json
{
  "planets": [
    {
      "id": "uuid",
      "name": "Planet Name",
      "sector_number": 100,
      "colonists": 10000,
      "colonists_max": 50000,
      "stock": {
        "ore": 5000,
        "organics": 3000,
        "goods": 2000,
        "energy": 8000,
        "credits": 15000
      },
      "defenses": {
        "fighters": 100,
        "torpedoes": 50,
        "shields": 200
      },
      "base": {
        "built": false,
        "cost": 50000
      }
    }
  ]
}
```

#### `POST /api/planet/claim`
Claim an unclaimed planet.

**Request Body:**
```json
{
  "planet_id": "uuid",
  "universe_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Planet claimed successfully",
  "planet_name": "Planet Name"
}
```

#### `POST /api/planet/rename`
Rename a planet.

**Request Body:**
```json
{
  "planet_id": "uuid",
  "name": "New Planet Name",
  "universe_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Planet renamed successfully"
}
```

#### `POST /api/planet/transfer`
Transfer resources between ship and planet.

**Request Body:**
```json
{
  "planet_id": "uuid",
  "action": "deposit",
  "resource": "credits",
  "amount": 1000,
  "universe_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Transferred 1000 credits to planet",
  "ship_credits": 9000,
  "planet_credits": 16000
}
```

#### `POST /api/planet/production-allocation`
Update planet production allocation.

**Request Body:**
```json
{
  "planet_id": "uuid",
  "allocations": {
    "ore": 30,
    "organics": 20,
    "goods": 25,
    "energy": 15,
    "fighters": 5,
    "torpedoes": 5
  },
  "universe_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Production allocation updated"
}
```

### Special Port

#### `POST /api/special-port/purchase`
Purchase equipment at special port.

**Request Body:**
```json
{
  "item_type": "hull",
  "universe_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Hull upgraded to level 2",
  "new_level": 2,
  "cost": 2000
}
```

### Combat

#### `POST /api/combat/initiate`
Initiate combat with another ship.

**Request Body:**
```json
{
  "target_ship_id": "uuid",
  "universe_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "combat_id": "uuid",
  "message": "Combat initiated"
}
```

### Trade Routes

#### `GET /api/trade-routes`
Get player's trade routes.

**Query Parameters:**
- `universe_id` (uuid): Universe ID

**Response:**
```json
{
  "routes": [
    {
      "id": "uuid",
      "name": "Ore Route",
      "from_sector": 100,
      "to_sector": 150,
      "resource": "ore",
      "active": true
    }
  ]
}
```

#### `POST /api/trade-routes`
Create a new trade route.

**Request Body:**
```json
{
  "name": "New Route",
  "from_sector": 100,
  "to_sector": 150,
  "resource": "ore",
  "universe_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "route_id": "uuid",
  "message": "Trade route created"
}
```

## Admin APIs

### Universe Management

#### `GET /api/admin/universes`
Get list of all universes.

**Response:**
```json
{
  "universes": [
    {
      "id": "uuid",
      "name": "Alpha",
      "sector_count": 500,
      "player_count": 5,
      "ai_count": 10,
      "created_at": "2025-01-01T00:00:00Z"
    }
  ]
}
```

#### `POST /api/admin/universes`
Create a new universe.

**Request Body:**
```json
{
  "name": "New Universe",
  "sector_count": 500
}
```

**Response:**
```json
{
  "success": true,
  "universe_id": "uuid",
  "message": "Universe created successfully"
}
```

#### `DELETE /api/admin/universes/[id]`
Destroy a universe.

**Response:**
```json
{
  "success": true,
  "message": "Universe destroyed successfully"
}
```

### AI Management

#### `GET /api/admin/ai-players`
Get AI players in a universe.

**Query Parameters:**
- `universe_id` (uuid): Universe ID

**Response:**
```json
{
  "ai_players": [
    {
      "id": "uuid",
      "handle": "AI_Alpha",
      "personality": "trader",
      "sector_number": 100,
      "credits": 50000,
      "planets_owned": 2,
      "turns_spent": 150
    }
  ]
}
```

#### `POST /api/admin/ai-players`
Create AI players in a universe.

**Request Body:**
```json
{
  "universe_id": "uuid",
  "count": 5
}
```

**Response:**
```json
{
  "success": true,
  "created_count": 5,
  "message": "AI players created successfully"
}
```

#### `POST /api/admin/trigger-ai-actions`
Manually trigger AI actions.

**Request Body:**
```json
{
  "universe_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "actions_taken": 15,
  "message": "AI actions completed"
}
```

### Universe Settings

#### `GET /api/admin/universe-settings`
Get universe settings.

**Query Parameters:**
- `universe_id` (uuid): Universe ID

**Response:**
```json
{
  "settings": {
    "ai_actions_enabled": true,
    "max_planets_per_sector": 3,
    "planets_needed_for_sector_ownership": 2,
    "igb_enabled": true,
    "igb_interest_rate_per_update": 0.01,
    "planet_interest_rate": 0.005
  }
}
```

#### `PUT /api/admin/universe-settings`
Update universe settings.

**Request Body:**
```json
{
  "universe_id": "uuid",
  "settings": {
    "ai_actions_enabled": true,
    "igb_interest_rate_per_update": 0.015
  }
}
```

**Response:**
```json
{
  "success": true,
  "message": "Settings updated successfully"
}
```

## Cron APIs

### `POST /api/cron/heartbeat`
Cron job heartbeat endpoint.

**Response:**
```json
{
  "success": true,
  "timestamp": "2025-01-01T00:00:00Z",
  "actions_taken": 25
}
```

### `POST /api/cron/tick`
Process game tick.

**Response:**
```json
{
  "success": true,
  "timestamp": "2025-01-01T00:00:00Z",
  "events_processed": 10
}
```

### `POST /api/cron/regen`
Regenerate resources.

**Response:**
```json
{
  "success": true,
  "timestamp": "2025-01-01T00:00:00Z",
  "resources_regenerated": 1000
}
```

## Error Responses

### Standard Error Format
```json
{
  "error": {
    "code": "error_code",
    "message": "Human readable error message",
    "details": "Additional error details"
  }
}
```

### Common Error Codes
- `unauthorized` - Authentication required
- `forbidden` - Insufficient permissions
- `not_found` - Resource not found
- `validation_error` - Invalid request data
- `insufficient_credits` - Not enough credits
- `insufficient_cargo` - Not enough cargo space
- `invalid_sector` - Invalid sector number
- `port_not_found` - Port not found
- `planet_not_found` - Planet not found
- `ship_not_found` - Ship not found
- `universe_not_found` - Universe not found

### HTTP Status Codes
- `200` - Success
- `400` - Bad Request
- `401` - Unauthorized
- `403` - Forbidden
- `404` - Not Found
- `500` - Internal Server Error

## Rate Limiting
- API calls are rate limited per user
- Cron endpoints have special rate limits
- AI actions are throttled to prevent spam

## Caching
- Sector data is cached for 30 seconds
- Ship data is cached for 10 seconds
- Map data is cached for 60 seconds
- Admin data is not cached

## WebSocket Events
Real-time updates via WebSocket for:
- Sector changes
- Ship movements
- Combat events
- Trade notifications
- AI actions
