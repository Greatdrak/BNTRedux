# BNT Redux Documentation

## Overview
This directory contains comprehensive documentation for the BNT Redux space trading game. The documentation is designed to be readable by both humans and AI assistants for future development and maintenance.

## Documentation Structure

### 📊 [Database Schema](DATABASE_SCHEMA.md)
Complete database documentation including:
- **Core Tables**: `universes`, `sectors`, `warps`, `players`, `ships`, `planets`, `ports`, `universe_settings`, `ai_player_memory`
- **Relationships**: Foreign key relationships and data flow
- **Functions**: All SQL functions with parameters and return types
- **Constraints**: Primary keys, unique constraints, foreign keys
- **Indexes**: Performance and unique indexes
- **Triggers**: Warp limits, timestamp updates
- **Generated Columns**: BNT capacity formulas
- **Security**: Row Level Security (RLS) policies
- **Performance**: Query optimization guidelines

### 🔌 [API Reference](API_REFERENCE.md)
Complete API documentation including:
- **Authentication**: Bearer token requirements
- **Core Game APIs**: Player management, sector info, ship management, movement, trading, planets
- **Admin APIs**: Universe management, AI management, universe settings
- **Cron APIs**: Automated game processing
- **Error Handling**: Standard error formats and codes
- **Rate Limiting**: API throttling and limits
- **Caching**: Data caching strategies
- **WebSocket Events**: Real-time updates

### 🤖 [AI System](AI_SYSTEM.md)
AI system architecture and implementation:
- **AI Personalities**: `trader`, `explorer`, `warrior`, `colonizer`, `balanced`
- **Memory System**: Persistent AI state and learning
- **Decision Making**: Multi-layered AI decision process
- **Functions**: Core AI functions and specialized behaviors
- **Integration**: Cron integration, turn tracking, game function usage
- **Performance**: Batch processing, memory optimization
- **Monitoring**: Statistics, debugging, troubleshooting
- **Configuration**: Universe settings and personality weights

## Key Technical Concepts

### Database Design
- **UUID Primary Keys**: All entities use UUID for primary keys
- **Generated Columns**: Ship capacities use BNT formula: `100 * (1.5^tech_level)`
- **Row Level Security**: Users can only access their own data
- **Universe Isolation**: Each universe is completely isolated
- **AI Memory**: Persistent AI state for intelligent behavior

### API Design
- **RESTful Endpoints**: Standard HTTP methods and status codes
- **JSON Responses**: Consistent response format
- **Authentication**: Bearer token in Authorization header
- **Error Handling**: Structured error responses with codes
- **Rate Limiting**: Prevents abuse and ensures performance

### AI System
- **Personality-Based**: AI behavior driven by personality types
- **Memory-Driven**: Persistent state for intelligent decisions
- **Game Function Integration**: AI uses same functions as human players
- **Turn Tracking**: AI actions consume turns like human players
- **Efficiency Scoring**: Performance metrics for AI optimization

## Development Guidelines

### Database Changes
1. **Create Migration**: Use numbered format `XXX_description.sql`
2. **Test Locally**: Verify migration works in development
3. **Update Documentation**: Update schema docs if structure changes
4. **Backup**: Create schema dump before major changes

### API Changes
1. **Update Documentation**: Document new endpoints or changes
2. **Version Compatibility**: Maintain backward compatibility when possible
3. **Error Handling**: Use standard error codes and formats
4. **Testing**: Test all endpoints with various scenarios

### AI System Changes
1. **Personality Behavior**: Document behavior changes for each personality
2. **Memory Schema**: Update memory table if adding new AI state
3. **Performance**: Consider impact on batch processing
4. **Testing**: Test AI behavior in various game scenarios

## Common Patterns

### Database Queries
```sql
-- Get player with ship and current sector
SELECT p.*, s.*, sec.number as sector_number
FROM players p
JOIN ships s ON s.player_id = p.id
LEFT JOIN sectors sec ON p.current_sector = sec.id
WHERE p.id = $1;

-- Get sector with warps, ports, planets, ships
SELECT 
  sec.*,
  array_agg(DISTINCT w.to_sector) as warps,
  port.*,
  array_agg(DISTINCT p.*) as planets,
  array_agg(DISTINCT sh.*) as ships
FROM sectors sec
LEFT JOIN warps w ON w.from_sector_id = sec.id
LEFT JOIN ports port ON port.sector_id = sec.id
LEFT JOIN planets p ON p.sector_id = sec.id
LEFT JOIN players pl ON pl.current_sector = sec.id
LEFT JOIN ships sh ON sh.player_id = pl.id
WHERE sec.id = $1
GROUP BY sec.id, port.id;
```

### API Response Format
```json
{
  "success": true,
  "data": {
    // Response data
  },
  "message": "Operation completed successfully"
}
```

### Error Response Format
```json
{
  "error": {
    "code": "error_code",
    "message": "Human readable error message",
    "details": "Additional error details"
  }
}
```

### AI Decision Making
```sql
-- AI decision process
1. Load current memory state
2. Assess current situation (credits, cargo, location, threats)
3. Choose goal based on personality and situation
4. Plan specific actions to achieve goal
5. Execute actions using game functions
6. Update memory and efficiency scores
```

## Troubleshooting

### Common Database Issues
- **Foreign Key Violations**: Check relationship constraints
- **Unique Constraint Violations**: Check for duplicate data
- **Generated Column Errors**: Verify formula calculations
- **RLS Policy Issues**: Check user permissions

### Common API Issues
- **Authentication Errors**: Verify Bearer token
- **Validation Errors**: Check request body format
- **Permission Errors**: Check user access rights
- **Rate Limit Errors**: Implement proper throttling

### Common AI Issues
- **AI Not Taking Actions**: Check if AI is enabled in universe settings
- **Poor AI Performance**: Review efficiency scores and adjust weights
- **AI Getting Stuck**: Check memory state and reset if needed
- **High Resource Usage**: Optimize batch processing and queries

## Future Development

### Planned Features
- **Machine Learning**: AI that learns from human behavior
- **Cooperative AI**: AI players working together
- **Advanced Combat**: More complex combat system
- **Trade Routes**: Automated trading between sectors
- **Federation System**: Player alliances and diplomacy

### Performance Improvements
- **Parallel Processing**: Process multiple AI simultaneously
- **Caching**: Cache frequently accessed data
- **Database Optimization**: Further optimize queries and indexes
- **Scaling**: Support for larger numbers of players and AI

## Maintenance

### Regular Tasks
- **Schema Backups**: Create regular schema dumps
- **Performance Monitoring**: Monitor query performance and AI efficiency
- **Error Logging**: Review and address common errors
- **Documentation Updates**: Keep docs current with code changes

### Emergency Procedures
- **Database Recovery**: Restore from schema backups
- **AI System Reset**: Reset AI memory if needed
- **Universe Wipe**: Clean up corrupted universe data
- **Performance Issues**: Optimize queries and reduce AI load

## Contact and Support

For questions about the documentation or system architecture:
- Review the relevant documentation file
- Check the troubleshooting section
- Examine the code examples and patterns
- Test changes in development environment first

---

*This documentation is maintained alongside the codebase and should be updated whenever significant changes are made to the system.*
