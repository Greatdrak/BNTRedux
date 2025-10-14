import { supabaseAdmin } from '@/lib/supabase-server'

// AI Personality Types
export interface AIPersonality {
  type: string
  makeDecision(situation: any): AIDecision
}

// AI Decision Interface
export interface AIDecision {
  action: string
  turnsToSpend: number
  priority: number
  reason: string
}

// AI Service Class
export class AIService {
  // Try a single ship upgrade for a specific attribute if a special port exists in the sector
  private async tryUpgrade(userId: string, sectorId: string, universeId: string, attr: 'hull' | 'power' | 'computer'): Promise<boolean> {
    // Is there a special port in-sector?
    let { data: ports, error: portsError } = await supabaseAdmin
      .from('ports')
      .select('id')
      .eq('sector_id', sectorId)
      .eq('kind', 'special')
      .limit(1)

    // If not, hyperspace to sector 0 (guaranteed special port per current universe rules)
    if (portsError || !ports || ports.length === 0) {
      const { data: hyperRes, error: hyperErr } = await supabaseAdmin.rpc('game_hyperspace', {
        p_user_id: userId,
        p_target_sector_number: 0,
        p_universe_id: universeId
      })
      if (hyperErr || (hyperRes && hyperRes.error)) return false
      // Resolve sector 0 id
      const { data: specialSector, error: ssErr } = await supabaseAdmin
        .from('sectors')
        .select('id')
        .eq('universe_id', universeId)
        .eq('number', 0)
        .single()
      if (ssErr || !specialSector) return false
      sectorId = specialSector.id
    }

    const { data, error } = await supabaseAdmin.rpc('game_ship_upgrade', {
      p_user_id: userId,
      p_attr: attr,
      p_universe_id: universeId
    })

    if (error || (data && data.error)) return false
    return true
  }
  // Get AI personality based on player handle
  getPersonality(handle: string): AIPersonality {
    const personalityTypes = ['Trader', 'Explorer', 'Warrior', 'Colonizer', 'Balanced']
    const hash = handle.split('').reduce((a, b) => a + b.charCodeAt(0), 0)
    const type = personalityTypes[hash % personalityTypes.length]
    
    switch (type) {
      case 'Trader':
        return new TraderPersonality(this)
      case 'Explorer':
        return new ExplorerPersonality(this)
      case 'Warrior':
        return new WarriorPersonality(this)
      case 'Colonizer':
        return new ColonizerPersonality(this)
      default:
        return new BalancedPersonality(this)
    }
  }
  
  // Helper to check if combat supplies need refilling
  checkCombatReadiness(situation: any): { needsRefill: boolean; fighterPercent: number; torpedoPercent: number; armorPercent: number } {
    const { shipLevels, fighters, torpedoes, armorPoints } = situation
    
    // Calculate capacities
    const fighterCapacity = Math.floor(100 * Math.pow(1.5, (shipLevels?.computer || 1) - 1))
    const torpedoCapacity = (shipLevels?.torpLauncher || 0) * 100
    const armorCapacity = Math.floor(100 * Math.pow(1.5, shipLevels?.armor || 1))
    
    // Calculate percentages
    const fighterPercent = fighterCapacity > 0 ? (fighters || 0) / fighterCapacity : 1
    const torpedoPercent = torpedoCapacity > 0 ? (torpedoes || 0) / torpedoCapacity : 1
    const armorPercent = armorCapacity > 0 ? (armorPoints || 0) / armorCapacity : 1
    
    // Need refill if any are below 50%
    const needsRefill = fighterPercent < 0.5 || torpedoPercent < 0.5 || armorPercent < 0.5
    
    // Combat status logging disabled for performance
    
    return { needsRefill, fighterPercent, torpedoPercent, armorPercent }
  }
  
  // Helper to calculate average tech level and determine if hoarding credits
  checkTechLevel(situation: any): { avgLevel: number; isHoarding: boolean } {
    const { shipLevels, credits } = situation
    
    const levels = [
      shipLevels?.hull || 0,
      shipLevels?.engine || 0,
      shipLevels?.computer || 0,
      shipLevels?.power || 0,
      shipLevels?.sensors || 0,
      shipLevels?.beamWeapon || 0,
      shipLevels?.torpLauncher || 0,
      shipLevels?.shields || 0,
      shipLevels?.armor || 0,
      shipLevels?.cloak || 0
    ]
    
    const avgLevel = levels.reduce((a, b) => a + b, 0) / levels.length
    
    // Calculate expected upgrade cost for current average level
    // Cost formula: 1000 * 2^level (doubles each time)
    const expectedCost = 1000 * Math.pow(2, Math.floor(avgLevel))
    
    // Hoarding if credits > 50x the expected upgrade cost AND average level < 15
    const isHoarding = credits > expectedCost * 50 && avgLevel < 15
    
    return { avgLevel, isHoarding }
  }
  
  // Analyze current situation
  async analyzeSituation(playerId: string, universeId: string): Promise<any> {
    try {
      // Get player data
      const { data: playerData, error: playerError } = await supabaseAdmin
        .from('players')
        .select(`
          id, handle, turns, current_sector,
          ships!inner(
            id, credits, hull, hull_max, ore, organics, goods, energy,
            fighters, torpedoes, armor,
            hull_lvl, engine_lvl, comp_lvl, power_lvl, sensor_lvl, 
            beam_lvl, torp_launcher_lvl, shield_lvl, armor_lvl, cloak_lvl
          )
        `)
        .eq('id', playerId)
        .limit(1)
      
      if (playerError || !playerData || playerData.length === 0) {
        throw new Error(`Failed to get player data: ${playerError?.message || 'No player found'}`)
      }
      
      const player = playerData[0]
      
      // Player analyzed (silent)
      
      const ship = Array.isArray(player.ships) ? player.ships[0] : player.ships
      
      // Ship levels are now in the ships table
      const shipLevels = {
        hull: ship.hull_lvl || 0,
        engine: ship.engine_lvl || 0,
        computer: ship.comp_lvl || 0,
        power: ship.power_lvl || 0,
        sensors: ship.sensor_lvl || 0,
        beamWeapon: ship.beam_lvl || 0,
        torpLauncher: ship.torp_launcher_lvl || 0,
        shields: ship.shield_lvl || 0,
        armor: ship.armor_lvl || 0,
        cloak: ship.cloak_lvl || 0
      }
      
      // Check if player has a current sector
      if (!player.current_sector) {
        throw new Error(`Player ${player.handle} has no current sector`)
      }
      
      // Get sector data
      const { data: sectorData, error: sectorError } = await supabaseAdmin
        .from('sectors')
        .select('id, number')
        .eq('id', player.current_sector)
        .single()
      
      if (sectorError || !sectorData) {
        throw new Error(`Failed to get sector data: ${sectorError?.message || 'Unknown error'}`)
      }
      
      // Get planets in sector
      const { data: planets, error: planetsError } = await supabaseAdmin
        .from('planets')
        .select('id, owner_player_id')
        .eq('sector_id', player.current_sector)
      
      const planetCount = planets?.length || 0
      const unclaimedPlanets = planets?.filter(p => !p.owner_player_id).length || 0
      
      // Get ports in sector
      const { data: ports, error: portsError } = await supabaseAdmin
        .from('ports')
        .select('kind')
        .eq('sector_id', player.current_sector)
      
      const portCount = ports?.length || 0
      const commodityPorts = ports?.filter(p => ['ore', 'organics', 'goods', 'energy'].includes(p.kind)).length || 0
      const specialPorts = ports?.filter(p => p.kind === 'special').length || 0
      
      // DEBUG: Log port information for sector 0 (only if no special port found)
      if (sectorData.number === 0 && specialPorts === 0) {
        // Sector 0 warning (logging disabled for performance)
      }
      
      // Get warps from sector
      const { data: warps, error: warpsError } = await supabaseAdmin
        .from('warps')
        .select('id')
        .eq('from_sector', player.current_sector)
      
      const warpCount = warps?.length || 0
      
      return {
        turns: player.turns || 0,
        credits: ship.credits || 0,
        hull: ship.hull || 0,
        hullMax: ship.hull_max || 0,
        fighters: ship.fighters || 0,
        torpedoes: ship.torpedoes || 0,
        armorPoints: ship.armor || 0,
        shipLevels,
        cargo: {
          ore: ship.ore || 0,
          organics: ship.organics || 0,
          goods: ship.goods || 0,
          energy: ship.energy || 0
        },
        ports: {
          total: portCount,
          commodity: commodityPorts,
          special: specialPorts
        },
        planets: {
          total: planetCount,
          unclaimed: unclaimedPlanets
        },
        warps: warpCount,
        sectorId: player.current_sector
      }
    } catch (error) {
      console.error('Error analyzing situation:', error)
      throw error
    }
  }
  
  // Execute hyperspace to a specific sector
  async executeHyperspace(playerId: string, targetSector: number, universeId: string): Promise<any> {
    try {
      const { data: result, error } = await supabaseAdmin.rpc('game_hyperspace', {
        p_user_id: playerId,
        p_target_sector_number: targetSector,
        p_universe_id: universeId
      })
      
      if (error) {
        return {
          success: false,
          actionsExecuted: 0,
          turnsUsed: 0,
          errors: [`Hyperspace failed: ${error.message || JSON.stringify(error)}`]
        }
      }
      
      if (result?.error) {
        const errorMsg = typeof result.error === 'string' ? result.error : 
                        result.error?.message || JSON.stringify(result.error)
        return {
          success: false,
          actionsExecuted: 0,
          turnsUsed: 0,
          errors: [`Hyperspace failed: ${errorMsg}`]
        }
      }
      
      return {
        success: true,
        actionsExecuted: 1,
        turnsUsed: 1,
        result: result
      }
    } catch (error) {
      return {
        success: false,
        actionsExecuted: 0,
        turnsUsed: 0,
        errors: [`Exception: ${error instanceof Error ? error.message : 'Unknown error'}`]
      }
    }
  }

  // Execute AI action
  async executeAction(playerId: string, universeId: string, decision: AIDecision): Promise<any> {
    try {
      // Get player's current sector
      const { data: playerData, error: playerError } = await supabaseAdmin
        .from('players')
        .select('current_sector')
        .eq('user_id', playerId)
        .single()
      
      if (playerError || !playerData) {
        throw new Error(`Failed to get player sector: ${playerError?.message || 'Unknown error'}`)
      }
      
      const sectorId = playerData.current_sector
      
      let result: any = { success: false, actionsExecuted: 0, turnsUsed: 0 }
      
      try {
        switch (decision.action) {
          case 'trade_route':
            result = await this.executeTradeRoute(playerId, sectorId, decision.turnsToSpend, universeId)
            break
            
          case 'explore_deep':
            result = await this.executeDeepExploration(playerId, sectorId, decision.turnsToSpend, universeId)
            break
            
          case 'explore_sell':
            result = await this.executeExploreSell(playerId, sectorId, decision.turnsToSpend, universeId)
            break
            
          case 'patrol':
            result = await this.executePatrol(playerId, sectorId, decision.turnsToSpend, universeId)
            break
            
          case 'claim_planet':
            result = await this.executeClaimPlanet(playerId, sectorId, decision.turnsToSpend, universeId)
            break
            
          case 'upgrade_ship':
            result = await this.executeUpgradeShip(playerId, sectorId, decision.turnsToSpend, universeId)
            break
            
          case 'develop_planets':
            result = await this.executeDevelopPlanets(playerId, sectorId, decision.turnsToSpend, universeId)
            break
            
          case 'emergency_trade':
            result = await this.executeTradeRoute(playerId, sectorId, decision.turnsToSpend, universeId)
            break
            
          case 'purchase_combat_equipment':
            result = await this.executePurchaseCombatEquipment(playerId, sectorId, decision.turnsToSpend, universeId)
            break
            
          case 'explore':
            result = await this.executeExplore(playerId, sectorId, decision.turnsToSpend, universeId)
            break
            
          case 'hyperspace':
            result = await this.executeHyperspace(playerId, 0, universeId) // Always hyperspace to sector 0
            break
            
          case 'wait':
            result = { success: true, actionsExecuted: 0, turnsUsed: 0 }
            break
            
          default:
            result = { success: false, actionsExecuted: 0, turnsUsed: 0, errors: ['Unknown action'] }
        }
      } catch (error) {
        result = { 
          success: false, 
          actionsExecuted: 0, 
          turnsUsed: 0, 
          errors: [error instanceof Error ? error.message : 'Unknown error'] 
        }
      }
      
      // If chosen action didn't use any turns, fall back to a short explore to ensure progress
      if ((result?.turnsUsed || 0) === 0 && (decision?.turnsToSpend || 0) > 0 && decision.action !== 'explore' && decision.action !== 'explore_deep') {
        const fallback = await this.executeExplore(playerId, sectorId, Math.min(decision.turnsToSpend, 10), universeId)
        result = {
          success: (result?.success || false) || (fallback?.success || false),
          actionsExecuted: (result?.actionsExecuted || 0) + (fallback?.actionsExecuted || 0),
          turnsUsed: (result?.turnsUsed || 0) + (fallback?.turnsUsed || 0),
          errors: [...(result?.errors || []), ...(fallback?.errors || [])]
        }
      }

      return {
        ...result,
        action: decision.action,
        reason: decision.reason,
        priority: decision.priority
      }
    } catch (error) {
      console.error('Error executing action:', error)
      return {
        success: false,
        actionsExecuted: 0,
        turnsUsed: 0,
        errors: [error instanceof Error ? error.message : 'Unknown error'],
        action: decision.action,
        reason: decision.reason,
        priority: decision.priority
      }
    }
  }
  
  // Smart AI trading - no complex routes needed
  private async executeSmartTrading(userId: string, sectorId: string, turnsToSpend: number, universeId: string) {
    let actionsExecuted = 0
    let turnsUsed = 0
    const errors: string[] = []
    
    // Get player_id from user_id
    const { data: player, error: playerError } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', userId)
      .single()
    
    if (playerError || !player) {
      errors.push(`Player lookup error: ${playerError?.message || 'Unknown error'}`)
      return { success: false, actionsExecuted: 0, turnsUsed: 0, errors }
    }
    
    // Get current ship cargo and credits
    const { data: shipData, error: shipError } = await supabaseAdmin
      .from('ships')
      .select('credits, ore, organics, goods, energy, cargo')
      .eq('player_id', player.id)
      .single()
    
    if (shipError || !shipData) {
      errors.push(`Ship data error: ${shipError?.message || 'Unknown error'}`)
      return { success: false, actionsExecuted: 0, turnsUsed: 0, errors }
    }
    
    const { credits, ore, organics, goods, energy, cargo } = shipData
    const cargoTotal = ore + organics + goods + energy
    
    // Get port prices in current sector
    const { data: portData, error: portError } = await supabaseAdmin
      .from('ports')
      .select('id, kind, ore, organics, goods, energy, price_ore, price_organics, price_goods, price_energy')
      .eq('sector_id', sectorId)
      .single()
    
    if (portError || !portData) {
      errors.push(`Port data error: ${portError?.message || 'Unknown error'}`)
      return { success: false, actionsExecuted: 0, turnsUsed: 0, errors }
    }
    
    // Smart trading logic: buy low, sell high
    for (let i = 0; i < Math.min(turnsToSpend, 15); i++) {
      try {
        let bestAction = null
        let bestProfit = 0
        
        // Check each commodity for trading opportunities
        const commodities = [
          { name: 'ore', price: portData.price_ore, stock: portData.ore },
          { name: 'organics', price: portData.price_organics, stock: portData.organics },
          { name: 'goods', price: portData.price_goods, stock: portData.goods },
          { name: 'energy', price: portData.price_energy, stock: portData.energy }
        ]
        
        for (const commodity of commodities) {
          // Buy if price is low and we have credits
          if (commodity.price < 100 && credits >= commodity.price * 2) {
            const profit = 150 - commodity.price // Expected profit
            if (profit > bestProfit) {
              bestAction = { type: 'buy', commodity: commodity.name, profit }
              bestProfit = profit
            }
          }
          
          // Sell if we have cargo and price is high
          const currentCargo = (shipData as any)[commodity.name] || 0
          if (currentCargo > 0 && commodity.price > 120) {
            const profit = commodity.price - 100 // Expected profit
            if (profit > bestProfit) {
              bestAction = { type: 'sell', commodity: commodity.name, profit }
              bestProfit = profit
            }
          }
        }
        
        if (bestAction) {
          const { data: result, error: tradeError } = await supabaseAdmin.rpc('game_trade', {
            p_user_id: userId,
            p_port_id: portData.id,
            p_action: bestAction.type,
            p_resource: bestAction.commodity,
            p_qty: 1,
            p_universe_id: universeId
          })
          
          if (tradeError) {
            errors.push(`Trade error: ${tradeError.message}`)
            continue
          }
          
          if (result?.success || result?.ok === true) {
            actionsExecuted++
            turnsUsed++
            
            // Update ship data for next iteration
            if (bestAction.type === 'buy') {
              (shipData as any)[bestAction.commodity] = ((shipData as any)[bestAction.commodity] || 0) + 1
              shipData.credits -= (portData as any)[`price_${bestAction.commodity}`]
            } else {
              (shipData as any)[bestAction.commodity] = Math.max(0, ((shipData as any)[bestAction.commodity] || 0) - 1)
              shipData.credits += (portData as any)[`price_${bestAction.commodity}`]
            }
          } else {
            errors.push(`Trade failed: ${result?.message || result?.error || 'Unknown error'}`)
          }
        } else {
          // No profitable trades available
          break
        }
      } catch (error) {
        errors.push(`Exception: ${error instanceof Error ? error.message : 'Unknown error'}`)
      }
    }
    
    return { 
      success: actionsExecuted > 0, 
      actionsExecuted, 
      turnsUsed,
      errors: errors.slice(0, 3)
    }
  }
  
  // Original trade route function - simple but effective
  private async executeTradeRoute(userId: string, sectorId: string, turnsToSpend: number, universeId: string) {
    let actionsExecuted = 0
    let turnsUsed = 0
    const errors: string[] = []
    
    for (let i = 0; i < Math.min(turnsToSpend, 20); i++) {
      try {
        // Get player_id from user_id first
        const { data: player, error: playerError } = await supabaseAdmin
          .from('players')
          .select('id')
          .eq('user_id', userId)
          .single()
        
        if (playerError || !player) {
          errors.push(`Player lookup error: ${playerError?.message || 'Unknown error'}`)
          continue
        }
        
        // Get current ship cargo to check capacity
        const { data: shipData, error: shipError } = await supabaseAdmin
          .from('ships')
          .select('ore, organics, goods, energy, cargo, hull_max')
          .eq('player_id', player.id)
          .single()
        
        if (shipError || !shipData) {
          errors.push(`Ship data error: ${shipError?.message || 'Unknown error'}`)
          continue
        }
        
        const { ore, organics, goods, energy, cargo, hull_max } = shipData
        // Energy does not consume cargo space
        const currentCargo = ore + organics + goods
        
        // If very low on credits but carrying cargo, prioritize selling to get a credit floor
        const currentCredits = (shipData as any).credits ?? 0
        if (currentCargo > 0 && currentCredits < 100) {
          const { data: ports, error: portsError } = await supabaseAdmin
            .from('ports')
            .select('id, kind')
            .eq('sector_id', sectorId)
            .in('kind', ['ore', 'organics', 'goods', 'energy'])
            .limit(1)

          if (portsError || !ports || ports.length === 0) {
            errors.push('Low credits and no ports to sell at')
            break
          }

          const port = ports[0]
          let resourceToSell: string | null = null
          const commodities = ['ore', 'organics', 'goods']
          for (const commodity of commodities) {
            if (commodity !== port.kind && (shipData as any)[commodity] > 0) {
              resourceToSell = commodity
              break
            }
          }

          if (!resourceToSell) {
            // No compatible cargo here—explore immediately to find a different market
            const fb = await this.executeExplore(userId, sectorId, Math.min(turnsToSpend, 10), universeId)
            actionsExecuted += fb.actionsExecuted || 0
            turnsUsed += fb.turnsUsed || 0
            if ((fb.errors || []).length) errors.push(...fb.errors!)
            break
          }

          const { data: result, error: tradeError } = await supabaseAdmin.rpc('game_trade', {
            p_user_id: userId,
            p_port_id: port.id,
            p_action: 'sell',
            p_resource: resourceToSell,
            p_qty: 1,
            p_universe_id: universeId
          })

          if (tradeError) {
            errors.push(`Sell error: ${tradeError.message}`)
            break
          }

          if (result?.success || result?.ok === true) {
            actionsExecuted++
            turnsUsed++
          } else {
            const errorMsg = (result && (result.error?.message || result.error)) || result?.message || 'Unknown error'
            errors.push(`Sell failed: ${errorMsg}`)
          }
          continue
        }

        // If ship is at capacity, try to sell cargo instead
        if (currentCargo >= hull_max) {
          // Try to sell cargo to make space
          // Ports buy all commodities EXCEPT their native commodity
          // Find a port and sell something OTHER than its native commodity
          const { data: ports, error: portsError } = await supabaseAdmin
            .from('ports')
            .select('id, kind')
            .eq('sector_id', sectorId)
            .in('kind', ['ore', 'organics', 'goods', 'energy'])
            .limit(1)

          if (portsError || !ports || ports.length === 0) {
            errors.push('Ship at capacity, no ports to sell at')
            continue
          }

          const port = ports[0]
          // Determine what commodity to sell (NOT the port's native commodity)
          // Sell whichever cargo we have that the port will buy
          let resourceToSell: string | null = null
          // Only sell cargo-bearing commodities; energy is excluded
          const commodities = ['ore', 'organics', 'goods']
          
          for (const commodity of commodities) {
            if (commodity !== port.kind && (shipData as any)[commodity] > 0) {
              resourceToSell = commodity
              break
            }
          }
          
          if (!resourceToSell) {
            errors.push('Ship at capacity, no compatible cargo to sell')
            // Can't trade here, so break out and the AI should explore instead
            break
          }

          const { data: result, error: tradeError } = await supabaseAdmin.rpc('game_trade', {
            p_user_id: userId,
            p_port_id: port.id,
            p_action: 'sell',
            p_resource: resourceToSell, // Sell a commodity the port will buy (NOT its native commodity)
            p_qty: 1,
            p_universe_id: universeId
          })

          if (tradeError) {
            errors.push(`Sell error: ${tradeError.message}`)
            continue
          }

          if (result?.success) {
            actionsExecuted++
            turnsUsed++
          } else {
            const errorMsg = (result && (result.error?.message || result.error)) || result?.message || 'Unknown error'
            errors.push(`Sell failed: ${errorMsg}`)
          }
          continue
        }

        // Find commodity port
        const { data: ports, error: portsError } = await supabaseAdmin
          .from('ports')
          .select('id, kind')
          .eq('sector_id', sectorId)
          .in('kind', ['ore', 'organics', 'goods', 'energy'])
          .limit(1)

        if (portsError) {
          errors.push(`Port query error: ${portsError.message}`)
          continue
        }

        if (ports && ports.length > 0) {
          const port = ports[0]
          // If commodity is energy and ship has zero energy capacity (power too low), try a power upgrade first
          if (port.kind === 'energy') {
            const upgraded = await this.tryUpgrade(userId, sectorId, universeId, 'power')
            // proceed regardless; if upgrade failed, RPC will return capacity error which we surface
          }
          const { data: result, error: tradeError } = await supabaseAdmin.rpc('game_trade', {
            p_user_id: userId,
            p_port_id: port.id,
            p_action: 'buy',
            p_resource: port.kind, // Buy the port's native commodity
            p_qty: 1,
            p_universe_id: universeId
          })

          if (tradeError) {
            errors.push(`Trade error: ${tradeError.message}`)
            continue
          }

          if (result?.success || result?.ok === true) {
            actionsExecuted++
            turnsUsed++
          } else {
            const errorMsg = (result && (result.error?.message || result.error)) || result?.message || 'Unknown error'
            errors.push(`Trade failed: ${errorMsg}`)
          }
        } else {
          // No ports here. If we need a special port (sector 0), hyperspace there cheaply, then resume.
          const { data: hyperResult, error: hyperErr } = await supabaseAdmin.rpc('game_hyperspace', {
            p_user_id: userId,
            p_target_sector_number: 0,
            p_universe_id: universeId
          })
          if (hyperErr || (hyperResult && hyperResult.error)) {
            // Fall back to explore if hyperspace not allowed
            const fallback = await this.executeExplore(userId, sectorId, Math.min(turnsToSpend, 10), universeId)
            actionsExecuted += fallback.actionsExecuted || 0
            turnsUsed += fallback.turnsUsed || 0
            if ((fallback.errors || []).length) errors.push(...fallback.errors!)
            break
          }
          // After hyperspace to 0, attempt to buy again next iteration
          continue
        }
      } catch (error) {
        errors.push(`Exception: ${error instanceof Error ? error.message : 'Unknown error'}`)
      }
    }

    return {
      success: actionsExecuted > 0,
      actionsExecuted,
      turnsUsed,
      errors: errors.slice(0, 3) // Limit to first 3 errors
    }
  }

  // Individual action executors
  private async executeDeepExploration(userId: string, sectorId: string, turnsToSpend: number, universeId: string) {
    let actionsExecuted = 0
    let turnsUsed = 0
    let currentSectorId = sectorId
    const errors: string[] = []
    
    for (let i = 0; i < Math.min(turnsToSpend, 30); i++) {
      try {
        // Get available warps
        const { data: warps, error: warpsError } = await supabaseAdmin
          .from('warps')
          .select('to_sector')
          .eq('from_sector', currentSectorId)
        
        if (warpsError) {
          errors.push(`Warps query error: ${warpsError.message}`)
          continue
        }
        
        if (warps && warps.length > 0) {
          const randomWarp = warps[Math.floor(Math.random() * warps.length)]
          
          // Get the sector number for the target sector
          const { data: targetSector, error: sectorError } = await supabaseAdmin
            .from('sectors')
            .select('number')
            .eq('id', randomWarp.to_sector)
            .single()
          
          if (sectorError || !targetSector) {
            errors.push(`Sector lookup error: ${sectorError?.message || 'Unknown error'}`)
            continue
          }
          
          const { data: result, error: moveError } = await supabaseAdmin.rpc('game_move', {
            p_user_id: userId,
            p_to_sector_number: targetSector.number,
            p_universe_id: universeId
          })
          
          if (moveError) {
            errors.push(`Move error: ${moveError.message}`)
            continue
          }
          
          if (!result?.ok && !result?.success) {
            errors.push(`Move failed: ${result?.message || result?.error || JSON.stringify(result) || 'Unknown error'}`)
            continue
          }
          
          if (result?.ok || result?.success) {
            actionsExecuted++
            turnsUsed++
            
            // Update current sector for next iteration
            currentSectorId = randomWarp.to_sector
          } else {
            errors.push(`Move failed: ${result?.message || result?.error || 'Unknown error'}`)
          }
        } else {
          errors.push('No warps found')
        }
      } catch (error) {
        errors.push(`Exception: ${error instanceof Error ? error.message : 'Unknown error'}`)
      }
    }
    
    return { 
      success: actionsExecuted > 0, 
      actionsExecuted, 
      turnsUsed,
      errors: errors.slice(0, 3)
    }
  }
  
  private async executeExploreSell(userId: string, sectorId: string, turnsToSpend: number, universeId: string) {
    // Similar to deep exploration but with selling focus
    return this.executeDeepExploration(userId, sectorId, Math.min(turnsToSpend, 15), universeId)
  }
  
  private async executePatrol(userId: string, sectorId: string, turnsToSpend: number, universeId: string) {
    // Similar to exploration but for patrolling
    return this.executeDeepExploration(userId, sectorId, Math.min(turnsToSpend, 20), universeId)
  }
  
  private async executeClaimPlanet(userId: string, sectorId: string, turnsToSpend: number, universeId: string) {
    // Get sector number from sector ID
    const { data: sector, error: sectorError } = await supabaseAdmin
      .from('sectors')
      .select('number')
      .eq('id', sectorId)
      .single()
    
    if (sectorError || !sector) {
      return { success: false, actionsExecuted: 0, turnsUsed: 0, errors: ['Failed to get sector number'] }
    }
    
    // Find unclaimed planet and claim it
    const { data: planets, error: planetsError } = await supabaseAdmin
      .from('planets')
      .select('id')
      .eq('sector_id', sectorId)
      .is('owner_player_id', null)
      .limit(1)
    
    if (planetsError || !planets || planets.length === 0) {
      return { success: false, actionsExecuted: 0, turnsUsed: 0, errors: ['No unclaimed planets found'] }
    }
    
    const { data: result, error: claimError } = await supabaseAdmin.rpc('game_planet_claim', {
      p_user_id: userId,
      p_sector_number: sector.number,
      p_name: 'AI Colony',
      p_universe_id: universeId
    })
    
    if (claimError) {
      return { success: false, actionsExecuted: 0, turnsUsed: 0, errors: [`Claim error: ${claimError.message}`] }
    }
    
    if (!result?.success && !result?.ok) {
      return { success: false, actionsExecuted: 0, turnsUsed: 0, errors: [`Claim failed: ${result?.message || JSON.stringify(result) || 'Unknown error'}`] }
    }
    
    return { 
      success: result?.success || false, 
      actionsExecuted: result?.success ? 1 : 0, 
      turnsUsed: result?.success ? 1 : 0,
      errors: result?.success ? [] : [result?.message || 'Unknown error']
    }
  }
  
  private async executeUpgradeShip(userId: string, sectorId: string, turnsToSpend: number, universeId: string) {
    // Find special port
    const { data: ports, error: portsError } = await supabaseAdmin
      .from('ports')
      .select('id')
      .eq('sector_id', sectorId)
      .eq('kind', 'special')
      .limit(1)
    
    if (portsError || !ports || ports.length === 0) {
      return { success: false, actionsExecuted: 0, turnsUsed: 0, errors: ['No special port found'] }
    }
    
    // Get player data to check current levels
    const { data: player, error: playerError } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', userId)
      .single()
    
    if (playerError || !player) {
      return { success: false, actionsExecuted: 0, turnsUsed: 0, errors: ['Player not found'] }
    }
    
    let successfulUpgrades = 0
    let turnsUsed = 0
    const errors: string[] = []
    
    // Get player's personality type to determine upgrade priority
    const { data: playerData } = await supabaseAdmin
      .from('players')
      .select('handle, is_ai')
      .eq('id', player.id)
      .single()
    
    let upgradeOrder: string[]
    
    if (playerData?.handle) {
      const personality = this.getPersonality(playerData.handle)
      
      if (personality.type === 'Warrior') {
        // Warriors prioritize weapons and combat systems
        upgradeOrder = ['beam', 'torp_launcher', 'shields', 'computer', 'sensors', 'cloak', 'armor', 'hull', 'engine', 'power']
      } else if (personality.type === 'Trader' || personality.type === 'Colonizer') {
        // Traders and Colonizers prioritize hull for cargo/economy
        upgradeOrder = ['hull', 'engine', 'computer', 'power', 'sensors', 'beam', 'shields', 'torp_launcher', 'armor', 'cloak']
      } else {
        // Balanced and Explorer: balanced approach with slight combat emphasis
        upgradeOrder = ['sensors', 'hull', 'beam', 'engine', 'torp_launcher', 'computer', 'shields', 'armor', 'cloak', 'power']
      }
    } else {
      // Default balanced order
      upgradeOrder = ['sensors', 'hull', 'beam', 'engine', 'torp_launcher', 'computer', 'shields', 'armor', 'cloak', 'power']
    }
    
    // Try upgrading each system - don't stop on first failure, try them all
    let consecutiveFailures = 0
    for (let i = 0; i < Math.min(turnsToSpend, 20); i++) {
      const upgradeType = upgradeOrder[i % upgradeOrder.length]
      
      const { data: result, error: upgradeError } = await supabaseAdmin.rpc('game_ship_upgrade', {
        p_user_id: userId,
        p_attr: upgradeType,
        p_universe_id: universeId
      })
      
      if (!upgradeError && result?.success) {
        successfulUpgrades++
        turnsUsed++
        consecutiveFailures = 0
      } else {
        consecutiveFailures++
        // Only stop if we've failed on ALL upgrade types (full cycle through the list)
        if (consecutiveFailures >= upgradeOrder.length) {
          break
        }
      }
      
      // Small delay to prevent overload
      await new Promise(resolve => setTimeout(resolve, 50))
    }
    
    // After upgrades, ALWAYS try to purchase fighters, torpedoes, and armor
    // This runs regardless of upgrade success to ensure combat readiness
    try {
      // Get current ship state to calculate capacities
      const { data: shipData } = await supabaseAdmin
        .from('ships')
        .select('credits, comp_lvl, torp_launcher_lvl, armor_lvl, fighters, torpedoes, armor')
        .eq('player_id', player.id)
        .single()
      
      if (shipData && shipData.credits >= 1000) {
        const purchases = []
        
        // Calculate capacities
        const fighterCapacity = Math.floor(100 * Math.pow(1.5, shipData.comp_lvl - 1))
        const torpedoCapacity = shipData.torp_launcher_lvl * 100
        const armorCapacity = Math.floor(100 * Math.pow(1.5, shipData.armor_lvl))
        
        const currentFighters = shipData.fighters || 0
        const currentTorpedoes = shipData.torpedoes || 0
        const currentArmor = shipData.armor || 0
        
        // ALWAYS max-buy fighters to full capacity (if capacity > 0)
        if (fighterCapacity > 0 && currentFighters < fighterCapacity) {
          const fightersToBuy = fighterCapacity - currentFighters
          if (fightersToBuy > 0 && shipData.credits >= fightersToBuy * 100) {
            purchases.push({
              name: 'Fighters',
              quantity: fightersToBuy,
              cost: 100
            })
          }
        }
        
        // ALWAYS max-buy torpedoes to full capacity (if capacity > 0)
        if (torpedoCapacity > 0 && currentTorpedoes < torpedoCapacity) {
          const torpedoesToBuy = torpedoCapacity - currentTorpedoes
          if (torpedoesToBuy > 0 && shipData.credits >= torpedoesToBuy * 200) {
            purchases.push({
              name: 'Torpedoes',
              quantity: torpedoesToBuy,
              cost: 200
            })
          }
        }
        
        // ALWAYS max-buy armor to full capacity (if capacity > 0)
        if (armorCapacity > 0 && currentArmor < armorCapacity) {
          const armorToBuy = armorCapacity - currentArmor
          if (armorToBuy > 0 && shipData.credits >= armorToBuy * 50) {
            purchases.push({
              name: 'Armor Points',
              quantity: armorToBuy,
              cost: 50
            })
          }
        }
        
        // Make purchases if any
        if (purchases.length > 0) {
          // Attempting purchase (logging disabled for performance)
          
          const { data: purchaseResult, error: purchaseError } = await supabaseAdmin
            .rpc('purchase_special_port_items', {
              p_player_id: player.id,
              p_purchases: purchases
            })
          
          if (!purchaseError && purchaseResult?.success) {
            // Purchases succeeded but don't count as turns
            successfulUpgrades += purchases.length
          }
        }
      } else {
        // Insufficient credits (logging disabled for performance)
      }
    } catch (purchaseError) {
      // Don't fail the whole operation if purchases fail (logging disabled for performance)
    }
    
    return { 
      success: successfulUpgrades > 0, 
      actionsExecuted: successfulUpgrades, 
      turnsUsed,
      action: 'upgrade',
      errors
    }
  }
  
  private async executeDevelopPlanets(userId: string, sectorId: string, turnsToSpend: number, universeId: string) {
    // For now, just explore (can be enhanced later with planet management)
    return this.executeDeepExploration(userId, sectorId, Math.min(turnsToSpend, 15), universeId)
  }
  
  private async executePurchaseCombatEquipment(userId: string, sectorId: string, turnsToSpend: number, universeId: string) {
    // Find special port
    const { data: ports, error: portsError } = await supabaseAdmin
      .from('ports')
      .select('id')
      .eq('sector_id', sectorId)
      .eq('kind', 'special')
      .limit(1)
    
    if (portsError || !ports || ports.length === 0) {
      return { success: false, actionsExecuted: 0, turnsUsed: 0, errors: ['No special port found'] }
    }
    
    // Get player data
    const { data: player, error: playerError } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', userId)
      .single()
    
    if (playerError || !player) {
      return { success: false, actionsExecuted: 0, turnsUsed: 0, errors: ['Player not found'] }
    }
    
    try {
      // Get current ship state to calculate capacities
      const { data: shipData } = await supabaseAdmin
        .from('ships')
        .select('credits, comp_lvl, torp_launcher_lvl, armor_lvl, fighters, torpedoes, armor')
        .eq('player_id', player.id)
        .single()
      
      if (!shipData) {
        return { success: false, actionsExecuted: 0, turnsUsed: 0, errors: ['Ship not found'] }
      }
      
      const purchases = []
      
      // Calculate capacities
      const fighterCapacity = Math.floor(100 * Math.pow(1.5, shipData.comp_lvl - 1))
      const torpedoCapacity = shipData.torp_launcher_lvl * 100
      const armorCapacity = Math.floor(100 * Math.pow(1.5, shipData.armor_lvl))
      
      const currentFighters = shipData.fighters || 0
      const currentTorpedoes = shipData.torpedoes || 0
      const currentArmor = shipData.armor || 0
      
      // ALWAYS max-buy fighters to full capacity (if capacity > 0)
      if (fighterCapacity > 0 && currentFighters < fighterCapacity) {
        const fightersToBuy = fighterCapacity - currentFighters
        if (fightersToBuy > 0 && shipData.credits >= fightersToBuy * 100) {
          purchases.push({
            name: 'Fighters',
            quantity: fightersToBuy,
            cost: 100
          })
        }
      }
      
      // ALWAYS max-buy torpedoes to full capacity (if capacity > 0)
      if (torpedoCapacity > 0 && currentTorpedoes < torpedoCapacity) {
        const torpedoesToBuy = torpedoCapacity - currentTorpedoes
        if (torpedoesToBuy > 0 && shipData.credits >= torpedoesToBuy * 200) {
          purchases.push({
            name: 'Torpedoes',
            quantity: torpedoesToBuy,
            cost: 200
          })
        }
      }
      
      // ALWAYS max-buy armor to full capacity (if capacity > 0)
      if (armorCapacity > 0 && currentArmor < armorCapacity) {
        const armorToBuy = armorCapacity - currentArmor
        if (armorToBuy > 0 && shipData.credits >= armorToBuy * 50) {
          purchases.push({
            name: 'Armor Points',
            quantity: armorToBuy,
            cost: 50
          })
        }
      }
      
      // Make purchases if any
      if (purchases.length > 0) {
        // Attempting dedicated purchase (logging disabled for performance)
        
        const { data: purchaseResult, error: purchaseError } = await supabaseAdmin
          .rpc('purchase_special_port_items', {
            p_player_id: player.id,
            p_purchases: purchases
          })
        
        if (!purchaseError && purchaseResult?.success) {
          return { 
            success: true, 
            actionsExecuted: 1, 
            turnsUsed: 0, // Purchases don't use turns
            action: 'purchase_combat_equipment'
          }
        } else {
          return { 
            success: false, 
            actionsExecuted: 0, 
            turnsUsed: 0,
            errors: [purchaseError?.message || purchaseResult?.error || 'Purchase failed']
          }
        }
      } else {
        // No purchases needed (logging disabled for performance)
        return { 
          success: true, 
          actionsExecuted: 0, 
          turnsUsed: 0,
          action: 'purchase_combat_equipment'
        }
      }
    } catch (purchaseError) {
      // Purchase error (logging disabled for performance)
      return { 
        success: false, 
        actionsExecuted: 0, 
        turnsUsed: 0,
        errors: [purchaseError instanceof Error ? purchaseError.message : 'Unknown error']
      }
    }
  }
  
  private async executeExplore(userId: string, sectorId: string, turnsToSpend: number, universeId: string) {
    // Simple exploration
    return this.executeDeepExploration(userId, sectorId, Math.min(turnsToSpend, 10), universeId)
  }
  
  // Competitive Balance System - Create multiple tiers of AI players across human score ranges
  async applyCommunismBoost(universeId: string): Promise<any> {
    try {
      // Refresh scores first to ensure they're up to date
      try {
        await supabaseAdmin.rpc('refresh_all_player_scores', { p_universe_id: universeId })
      } catch (e) {
        console.warn('Score refresh in communism boost failed', e)
      }

      // Get all human players sorted by score with their tech levels
      const { data: humanPlayersData, error: humanError } = await supabaseAdmin
        .from('players')
        .select(`
          id, score,
          ships!inner(hull_lvl, engine_lvl, comp_lvl, sensor_lvl, beam_lvl, torp_launcher_lvl, shield_lvl, armor_lvl, cloak_lvl, power_lvl)
        `)
        .eq('universe_id', universeId)
        .eq('is_ai', false)
        .order('score', { ascending: false })
      
      if (humanError || !humanPlayersData || humanPlayersData.length === 0) {
        return { success: false, message: 'No human players found' }
      }

      // Get all AI players with their current data
      const { data: aiPlayersAll, error: aiError } = await supabaseAdmin
        .from('players')
        .select(`
          id, handle, score, user_id,
          ships!inner(credits, hull_lvl, engine_lvl, comp_lvl, sensor_lvl, beam_lvl, torp_launcher_lvl, shield_lvl, armor_lvl, cloak_lvl, power_lvl)
        `)
        .eq('universe_id', universeId)
        .eq('is_ai', true)
        .order('score', { ascending: false })
      
      if (aiError || !aiPlayersAll || aiPlayersAll.length === 0) {
        return { success: false, message: 'No AI players found' }
      }
      
      // Calculate average tech levels for humans
      const humanTechLevels = humanPlayersData.map(p => {
        const ship = Array.isArray(p.ships) ? p.ships[0] : p.ships
        return {
          hull: ship.hull_lvl || 1,
          engine: ship.engine_lvl || 1,
          computer: ship.comp_lvl || 1,
          sensors: ship.sensor_lvl || 1,
          beam: ship.beam_lvl || 1,
          torpLauncher: ship.torp_launcher_lvl || 0,
          shields: ship.shield_lvl || 0,
          armor: ship.armor_lvl || 1,
          cloak: ship.cloak_lvl || 0,
          power: ship.power_lvl || 1
        }
      })
      
      // Calculate median tech level for each system
      const techSystems = ['hull', 'engine', 'computer', 'sensors', 'beam', 'torpLauncher', 'shields', 'armor', 'cloak', 'power'] as const
      const humanMedianTech: Record<string, number> = {}
      
      for (const system of techSystems) {
        const levels = humanTechLevels.map(t => t[system]).sort((a, b) => a - b)
        const midIndex = Math.floor(levels.length / 2)
        humanMedianTech[system] = levels.length % 2 === 0 
          ? Math.floor((levels[midIndex - 1] + levels[midIndex]) / 2)
          : levels[midIndex]
      }
      
      // Calculate average tech level across all systems for humans
      const humanAvgTechLevel = Object.values(humanMedianTech).reduce((sum, val) => sum + val, 0) / techSystems.length
      
      // Calculate standard deviation of human tech levels
      const humanTechVariances = humanTechLevels.map(tech => {
        const avgTech = Object.values(tech).reduce((sum, val) => sum + val, 0) / techSystems.length
        return Math.pow(avgTech - humanAvgTechLevel, 2)
      })
      const humanTechStdDev = Math.sqrt(humanTechVariances.reduce((sum, val) => sum + val, 0) / humanTechVariances.length)
      
      // Tech analysis (logging disabled for performance)

      // PHASE 1: Automated Tech Leveling - Bring AI tech up to competitive levels
      // Target: AI should be within 2 standard deviations of median human tech (more conservative)
      // Only upgrade AI that are significantly behind to prevent score inflation
      const techUpgradeResults = []
      let totalTechUpgrades = 0
      
      for (const aiPlayer of aiPlayersAll) {
        const ship = Array.isArray(aiPlayer.ships) ? aiPlayer.ships[0] : aiPlayer.ships
        const aiTech = {
          hull: ship.hull_lvl || 1,
          engine: ship.engine_lvl || 1,
          computer: ship.comp_lvl || 1,
          sensors: ship.sensor_lvl || 1,
          beam: ship.beam_lvl || 1,
          torpLauncher: ship.torp_launcher_lvl || 0,
          shields: ship.shield_lvl || 0,
          armor: ship.armor_lvl || 1,
          cloak: ship.cloak_lvl || 0,
          power: ship.power_lvl || 1
        }
        
        // Calculate AI average tech level
        const aiAvgTech = Object.values(aiTech).reduce((sum, val) => sum + val, 0) / techSystems.length
        
        // Check if AI is more than 2 standard deviations below human median (more conservative)
        const techDeficit = humanAvgTechLevel - aiAvgTech
        
        if (techDeficit > (humanTechStdDev * 2)) {
          // AI needs tech upgrades - apply direct upgrades to lagging systems
          const upgradeMap: Record<string, string> = {
            hull: 'hull',
            engine: 'engine',
            computer: 'computer',
            sensors: 'sensors',
            beam: 'beam',
            torpLauncher: 'torp_launcher',
            shields: 'shields',
            armor: 'armor',
            cloak: 'cloak',
            power: 'power'
          }
          
          let upgradesApplied = 0
          for (const system of techSystems) {
            const aiLevel = aiTech[system]
            const humanMedianLevel = humanMedianTech[system]
            
            // If AI is 3+ levels behind median, apply direct upgrades (more conservative)
            if (humanMedianLevel - aiLevel >= 3) {
              const levelsToUpgrade = Math.min(humanMedianLevel - aiLevel, 1) // Max 1 level per system per boost
              
              // Use admin function to bypass port/credit requirements
              const { data: upgradeResult, error: upgradeError } = await supabaseAdmin.rpc('admin_force_ship_upgrade', {
                p_player_id: aiPlayer.id,
                p_attr: upgradeMap[system],
                p_levels: levelsToUpgrade
              })
              
              if (!upgradeError && upgradeResult?.success) {
                upgradesApplied += upgradeResult.levels_applied || levelsToUpgrade
                totalTechUpgrades += upgradeResult.levels_applied || levelsToUpgrade
              }
              
              // Small delay to prevent overload
              await new Promise(resolve => setTimeout(resolve, 25))
            }
          }
          
          if (upgradesApplied > 0) {
            techUpgradeResults.push({
              player: aiPlayer.handle,
              aiAvgTech: aiAvgTech.toFixed(2),
              humanAvgTech: humanAvgTechLevel.toFixed(2),
              techDeficit: techDeficit.toFixed(2),
              upgradesApplied
            })
          }
        }
      }
      
      // Tech upgrades applied (logging disabled for performance)
      
      const humanScores = humanPlayersData.map(p => p.score || 0).sort((a, b) => b - a)
      const aiScores = aiPlayersAll.map(p => p.score || 0).sort((a, b) => b - a)
      
      const humanTop = humanScores[0] || 0
      const humanMedian = humanScores[Math.floor(humanScores.length / 2)] || 0
      const humanBottom = humanScores[humanScores.length - 1] || 0
      
      const aiTop = aiScores[0] || 0
      const aiMedian = aiScores[Math.floor(aiScores.length / 2)] || 0
      const aiBottom = aiScores[aiScores.length - 1] || 0

      // Calculate score distribution width
      const humanRange = humanTop - humanBottom
      const aiRange = aiTop - aiBottom
      const totalRange = Math.max(humanTop, aiTop) - Math.min(humanBottom, aiBottom)
      
      // Check if AI distribution is too narrow (all clustered together)
      const aiDistributionTooNarrow = aiRange < (totalRange * 0.3) // AI should span at least 30% of total range
      
      // Check if AI are too far behind humans
      const aiTooFarBehind = aiMedian < (humanMedian * 0.5)
      
      // Check if top AI is too far ahead (creating permanent gap)
      const aiTopTooFarAhead = aiTop > (aiMedian * 3.0)
      
      // Balance check (logging disabled for performance)

      // Only boost if we need to create better distribution
      if (!aiDistributionTooNarrow && !aiTooFarBehind && !aiTopTooFarAhead) {
        return {
          success: true,
          message: 'AI distribution is balanced - no boost needed',
          humanRange,
          aiRange,
          humanTop,
          humanMedian,
          aiTop,
          aiMedian
        }
      }

      // Calculate target tiers: AI should be distributed across human score ranges
      // Boost amounts are PROPORTIONAL to the score economy, not hard-capped
      const targetTiers = [
        { name: 'Elite AI', targetScore: Math.floor(humanTop * 0.9), targetPercent: 0.9 },      // 90% of top human
        { name: 'Advanced AI', targetScore: Math.floor(humanMedian * 1.2), targetPercent: 1.2 }, // 120% of median human (relative to median)
        { name: 'Standard AI', targetScore: Math.floor(humanMedian * 0.8), targetPercent: 0.8 }, // 80% of median human
        { name: 'Beginner AI', targetScore: Math.floor(humanBottom * 1.5), targetPercent: 1.5 }  // 150% of bottom human (relative to bottom)
      ]

      let totalBoosted = 0
      const boostResults = []

      for (const tier of targetTiers) {
        // Find AI players that should be in this tier
        const tierAIs = aiPlayersAll.filter(ai => {
          const currentScore = ai.score || 0
          // Include AI that are significantly below this tier's target
          return currentScore < (tier.targetScore * 0.7) && currentScore > (tier.targetScore * 0.3)
        })

        if (tierAIs.length === 0) continue

        // Boosting tier (logging disabled for performance)

        for (const player of tierAIs) {
          const ship = Array.isArray(player.ships) ? player.ships[0] : player.ships
          const currentCredits = ship.credits || 0
          
          // Calculate how much boost this AI needs - PROPORTIONAL TO SCORE GAP
          const currentScore = player.score || 0
          const scoreGap = Math.max(0, tier.targetScore - currentScore)
          
          // Score is roughly: (ship_tech_value + credits + planet_value + exploration) / 100
          // So to gain X score points, need roughly X * 100 in raw value
          // Give 60% as pure credits (rest they can earn via trading/upgrades)
          const creditNeeded = Math.floor(scoreGap * 100 * 0.6)
          
          if (creditNeeded > 10000) { // Only boost if significant gap
            const newCredits = currentCredits + creditNeeded
            
            // Update AI player's credits
            const { error: updateError } = await supabaseAdmin
              .from('ships')
              .update({ credits: newCredits })
              .eq('player_id', player.id)
            
            if (!updateError) {
              totalBoosted++
              boostResults.push({
                tier: tier.name,
                player: player.handle,
                oldCredits: currentCredits,
                newCredits: newCredits,
                boostAmount: creditNeeded,
                targetScore: tier.targetScore
              })

              // Try to spend credits on upgrades (limited to prevent runaway)
              const upgradeSequence = ['sensors', 'beam', 'torp_launcher', 'cloak', 'shields', 'armor', 'hull', 'engine', 'computer', 'power']
              
              for (let u = 0; u < 5; u++) { // Limit to 5 upgrades per boost
                const attr = upgradeSequence[u % upgradeSequence.length]
                const { data: upgradeData, error: upgradeErr } = await supabaseAdmin.rpc('game_ship_upgrade', {
                  p_user_id: player.user_id,
                  p_attr: attr,
                  p_universe_id: universeId
                })
                if (upgradeErr || !upgradeData?.success) break // Stop if upgrade fails
              }
            }
          }
        }
      }
      
      return {
        success: true,
        message: `Applied ${totalTechUpgrades} tech upgrades and tier-based boost to ${totalBoosted} AI players`,
        humanRange,
        aiRange,
        humanTop,
        humanMedian,
        aiTop,
        aiMedian,
        humanAvgTechLevel,
        humanTechStdDev,
        totalTechUpgrades,
        techUpgradeResults,
        totalBoosted,
        boostResults,
        targetTiers: targetTiers.map(t => ({ name: t.name, targetScore: t.targetScore }))
      }
      
    } catch (error) {
      console.error('Error applying communism boost:', error)
      return {
        success: false,
        message: `Failed to apply communism boost: ${error instanceof Error ? error.message : 'Unknown error'}`
      }
    }
  }

  // Process AI for a single universe - optimized for 100+ AI players
  async processUniverse(universeId: string): Promise<any> {
    try {
      // Get AI players with turns - limit to prevent performance issues
      const { data: aiPlayers, error: playersError } = await supabaseAdmin
        .from('players')
        .select(`
          id, handle, turns, user_id,
          ships(credits, hull, hull_max, ore, organics, goods, energy)
        `)
        .eq('universe_id', universeId)
        .eq('is_ai', true)
        .order('turns', { ascending: false })
      
      if (playersError) {
        throw new Error(`Failed to get AI players: ${playersError.message}`)
      }
      
      if (!aiPlayers || aiPlayers.length === 0) {
        return {
          success: true,
          message: 'No AI players with turns found',
          playersProcessed: 0,
          actionsTaken: 0,
          totalTurnsUsed: 0
        }
      }
      
      // ENSURE AI PLAYERS ALWAYS HAVE TURNS - Add 50 turns to any AI with < 10 turns
      const lowTurnAIs = aiPlayers.filter(p => (p.turns || 0) < 10)
      if (lowTurnAIs.length > 0) {
        await supabaseAdmin
          .from('players')
          .update({ turns: 50 })
          .in('id', lowTurnAIs.map(p => p.id))
        
        // Update the in-memory player data
        lowTurnAIs.forEach(p => p.turns = 50)
      }
      
      // Apply communism boost if needed (only once per cycle)
      const communismBoost = await this.applyCommunismBoost(universeId)
      
      // Regenerate AI combat supplies automatically
      try {
        const { data: regenResult, error: regenError } = await supabaseAdmin.rpc('ai_regenerate_combat_supplies', {
          p_universe_id: universeId
        })
        
        if (!regenError && regenResult?.success) {
          // Combat supplies regenerated successfully
        }
      } catch (regenError) {
        // Non-fatal error - combat supplies regeneration failed
      }
      
      const aiService = new AIService()
      let playersProcessed = 0
      let actionsTaken = 0
      let totalTurnsUsed = 0
      const actionBreakdown: any = {}
      const playerResults: any[] = []
      
      // Process AI players in batches for better performance
      const batchSize = 5
      for (let i = 0; i < aiPlayers.length; i += batchSize) {
        const batch = aiPlayers.slice(i, i + batchSize)
        
        // Process batch in parallel
        const batchPromises = batch.map(async (player) => {
          try {
            // Get personality
            const personality = aiService.getPersonality(player.handle)
            
            // Analyze situation
            const situation = await aiService.analyzeSituation(player.id, universeId)
            
            // Make decision
            // EMERGENCY: Force upgrade if sitting on huge credits with low hull LEVEL
            let decision
            if (situation.credits > 10000000 && situation.hullLevel < 10) {
              if (situation.ports.special === 0 && situation.turns >= 1) {
                // Not at special port - hyperspace to sector 0
                decision = {
                  action: 'hyperspace',
                  turnsToSpend: 1,
                  priority: 100,
                  reason: 'emergency_seek_special_port'
                }
              } else if (situation.ports.special > 0) {
                // At special port - UPGRADE NOW
                decision = {
                  action: 'upgrade_ship',
                  turnsToSpend: Math.min(situation.turns, 20),
                  priority: 100,
                  reason: 'emergency_upgrade'
                }
              } else {
                decision = personality.makeDecision(situation)
              }
            } else {
              decision = personality.makeDecision(situation)
            }
            
            // Execute action
            const result = await aiService.executeAction(player.user_id, universeId, decision)
            
            // Track errors (silent - errors are in playerResults)
            
            // Store simplified result
            playerResults.push({
              player: player.handle,
              action: decision.action,
              success: result.success,
              actionsExecuted: result.actionsExecuted || 0,
              turnsUsed: result.turnsUsed || 0,
              reason: decision.reason,
              error: result.errors?.[0] || null
            })
            
            return {
              success: result.success,
              actionsExecuted: result.actionsExecuted || 0,
              turnsUsed: result.turnsUsed || 0,
              actionType: result.action
            }
            
          } catch (error) {
            // Error processing AI (logging disabled for performance)
            playerResults.push({
              player: player.handle,
              action: 'error',
              success: false,
              actionsExecuted: 0,
              turnsUsed: 0,
              reason: 'processing_error',
              error: error instanceof Error ? error.message : 'Unknown error'
            })
            return {
              success: false,
              actionsExecuted: 0,
              turnsUsed: 0,
              actionType: 'error'
            }
          }
        })
        
        // Wait for batch to complete
        const batchResults = await Promise.all(batchPromises)
        
        // Aggregate results
        playersProcessed += batch.length
        batchResults.forEach(result => {
          if (result.success) {
            actionsTaken++
            totalTurnsUsed += result.turnsUsed
            
            // Track action types
            const actionType = result.actionType
            actionBreakdown[actionType] = (actionBreakdown[actionType] || 0) + 1
          }
        })
        
        // Small delay between batches to prevent database overload
        if (i + batchSize < aiPlayers.length) {
          await new Promise(resolve => setTimeout(resolve, 100))
        }
      }
      
      // Refresh scores for all players in the universe (now stored in DB)
      try {
        await supabaseAdmin.rpc('refresh_all_player_scores', { p_universe_id: universeId })
      } catch (e) {
        console.warn('Score refresh failed', e)
      }

      // Get top 10 AI players by score (now stored in players table)
      const { data: topAIPlayers } = await supabaseAdmin
        .from('players')
        .select('handle, score, turns')
        .eq('universe_id', universeId)
        .eq('is_ai', true)
        .order('score', { ascending: false })
        .limit(10)

      return {
        success: true,
        message: 'AI processing completed',
        aiTotal: aiPlayers.length,
        aiWithTurns: aiPlayers.length,
        playersProcessed,
        totalActions: actionsTaken,
        totalTurnsUsed,
        actionBreakdown,
        communismBoost: communismBoost.success ? {
          message: communismBoost.message,
          aisBoosted: communismBoost.boostedPlayers || 0,
          totalCreditsInjected: communismBoost.boostResults?.reduce((sum: number, r: any) => sum + (r.boostAmount || 0), 0) || 0,
          humanMedian: communismBoost.humanMedian,
          targetAIScore: communismBoost.targetAIScore
        } : null,
        topPlayers: topAIPlayers || []
      }
      
    } catch (error) {
      console.error('Error processing universe:', error)
      return {
        success: false,
        message: `Failed to process universe: ${error instanceof Error ? error.message : 'Unknown error'}`,
        playersProcessed: 0,
        actionsTaken: 0,
        totalTurnsUsed: 0
      }
    }
  }
}

// Personality Classes
class TraderPersonality implements AIPersonality {
  type = 'Trader'
  private aiService: AIService
  
  constructor(aiService: AIService) {
    this.aiService = aiService
  }
  
  makeDecision(situation: any): AIDecision {
    const { turns, credits, ports, planets, warps, hull, cargo, shipLevels } = situation
    // Energy does not take cargo space
    const cargoTotal = (cargo?.ore || 0) + (cargo?.organics || 0) + (cargo?.goods || 0)
    
    // Check combat readiness and tech level
    const combatStatus = this.aiService.checkCombatReadiness(situation)
    const techStatus = this.aiService.checkTechLevel(situation)
    
    // CRITICAL: Return to sector 0 if combat supplies below 50%
    if (combatStatus.needsRefill && ports.special === 0 && turns >= 1) {
      return {
        action: 'hyperspace',
        turnsToSpend: 1,
        priority: 97,
        reason: 'trader_refill_combat_supplies'
      }
    }
    
    // Combat supplies auto-regenerate now - no need to purchase
    
    // CRITICAL: Hoarding credits with low tech - MUST UPGRADE
    if (techStatus.isHoarding && ports.special > 0) {
      return {
        action: 'upgrade_ship',
        turnsToSpend: Math.min(turns, 20),
        priority: 99,
        reason: 'trader_stop_hoarding'
      }
    }
    
    // Seek special port if hoarding and not there
    if (techStatus.isHoarding && ports.special === 0 && turns >= 1) {
      return {
        action: 'hyperspace',
        turnsToSpend: 1,
        priority: 98,
        reason: 'trader_seek_upgrades'
      }
    }
    
    // Emergency trading - only if we have cargo to sell or ports to trade at
    if (credits < 500 && (cargoTotal > 10 || ports.commodity > 0)) {
      return {
        action: 'emergency_trade',
        turnsToSpend: Math.min(turns, 20),
        priority: 100,
        reason: 'trader_emergency'
      }
    }
    
    // Trade routes - be aggressive with turn spending
    if (turns >= 10 && ports.commodity > 0) {
      return {
        action: 'trade_route',
        turnsToSpend: Math.min(turns, 40),
        priority: 90,
        reason: 'trader_trading'
      }
    }
    
    // PRIORITY: Ship upgrades - be VERY aggressive with high credits!
    if (credits >= 2000 && ports.special > 0) {
      return {
        action: 'upgrade_ship',
        turnsToSpend: Math.min(turns, 15),
        priority: 95,
        reason: 'trader_upgrading'
      }
    }
    
    // CRITICAL: Seek special port for upgrades if we have lots of credits
    if (credits >= 2000 && ports.special === 0 && turns >= 3) {
      return {
        action: 'hyperspace',
        turnsToSpend: 1,
        priority: 93,
        reason: 'trader_seeking_special_port'
      }
    }
    
    // Exploration for new trading opportunities
    if (turns >= 5 && warps > 0) {
      return {
        action: 'explore',
        turnsToSpend: Math.min(turns, 15),
        priority: 70,
        reason: 'trader_exploring'
      }
    }
    
    return {
      action: 'wait',
      turnsToSpend: 0,
      priority: 0,
      reason: 'trader_no_turns'
    }
  }
}

class ExplorerPersonality implements AIPersonality {
  type = 'Explorer'
  private aiService: AIService
  
  constructor(aiService: AIService) {
    this.aiService = aiService
  }
  
  makeDecision(situation: any): AIDecision {
    const { turns, credits, ports, planets, warps, hull, cargo, shipLevels } = situation
    
    // Check combat readiness and tech level
    const combatStatus = this.aiService.checkCombatReadiness(situation)
    const techStatus = this.aiService.checkTechLevel(situation)
    
    // CRITICAL: Return to sector 0 if combat supplies below 50%
    if (combatStatus.needsRefill && ports.special === 0 && turns >= 1) {
      return {
        action: 'hyperspace',
        turnsToSpend: 1,
        priority: 97,
        reason: 'explorer_refill_combat_supplies'
      }
    }
    
    // Combat supplies auto-regenerate now - no need to purchase
    
    // CRITICAL: Hoarding credits with low tech - MUST UPGRADE
    if (techStatus.isHoarding && ports.special > 0) {
      return {
        action: 'upgrade_ship',
        turnsToSpend: Math.min(turns, 20),
        priority: 99,
        reason: 'explorer_stop_hoarding'
      }
    }
    
    // Seek special port if hoarding
    if (techStatus.isHoarding && ports.special === 0 && turns >= 1) {
      return {
        action: 'hyperspace',
        turnsToSpend: 1,
        priority: 98,
        reason: 'explorer_seek_upgrades'
      }
    }
    
    // Deep exploration - be very aggressive with turn spending
    if (turns >= 5 && warps > 0) {
      return {
        action: 'explore_deep',
        turnsToSpend: Math.min(turns, 50),
        priority: 95,
        reason: 'explorer_exploring'
      }
    }
    
    // Claim planets when found
    if (planets.unclaimed > 0 && credits >= 10000) {
      return {
        action: 'claim_planet',
        turnsToSpend: 1,
        priority: 85,
        reason: 'explorer_claiming'
      }
    }
    
    // Emergency trading for credits
    if (credits < 1000 && ports.commodity > 0) {
      return {
        action: 'emergency_trade',
        turnsToSpend: Math.min(turns, 10),
        priority: 80,
        reason: 'explorer_emergency'
      }
    }
    
    // Default: if any turns remain, explore rather than wait
    if (turns > 0 && warps > 0) {
      return {
        action: 'explore',
        turnsToSpend: Math.min(turns, 10),
        priority: 50,
        reason: 'explorer_default_explore'
      }
    }

    return { action: 'wait', turnsToSpend: 0, priority: 0, reason: 'explorer_no_turns' }
  }
}

class WarriorPersonality implements AIPersonality {
  type = 'Warrior'
  private aiService: AIService
  
  constructor(aiService: AIService) {
    this.aiService = aiService
  }
  
  makeDecision(situation: any): AIDecision {
    const { turns, credits, ports, planets, warps, hull, cargo, shipLevels } = situation
    
    // Check combat readiness and tech level
    const combatStatus = this.aiService.checkCombatReadiness(situation)
    const techStatus = this.aiService.checkTechLevel(situation)
    
    // CRITICAL: Warriors MUST stay combat ready - return to sector 0 if below 50%
    if (combatStatus.needsRefill && ports.special === 0 && turns >= 1) {
      return {
        action: 'hyperspace',
        turnsToSpend: 1,
        priority: 99, // HIGHEST priority for warriors!
        reason: 'warrior_refill_combat_supplies'
      }
    }
    
    // Combat supplies auto-regenerate now - no need to purchase
    
    // CRITICAL: Hoarding credits with low tech - MUST UPGRADE
    if (techStatus.isHoarding && ports.special > 0) {
      return {
        action: 'upgrade_ship',
        turnsToSpend: Math.min(turns, 25), // Warriors upgrade most aggressively
        priority: 100,
        reason: 'warrior_stop_hoarding'
      }
    }
    
    // Seek special port if hoarding
    if (techStatus.isHoarding && ports.special === 0 && turns >= 1) {
      return {
        action: 'hyperspace',
        turnsToSpend: 1,
        priority: 99,
        reason: 'warrior_seek_upgrades'
      }
    }
    
    // Ship upgrades for combat - warriors prioritize this ABOVE ALL!
    if (credits >= 1500 && ports.special > 0) {
      return {
        action: 'upgrade_ship',
        turnsToSpend: Math.min(turns, 20), // Warriors upgrade VERY aggressively
        priority: 98, // Highest priority!
        reason: 'warrior_upgrading'
      }
    }
    
    // Seek special port for upgrades - CRITICAL
    if (credits >= 1500 && ports.special === 0 && turns >= 3) {
      return {
        action: 'hyperspace',
        turnsToSpend: 1,
        priority: 96, // Must find special port!
        reason: 'warrior_seeking_special_port'
      }
    }
    
    // Claim planets for territory
    if (planets.unclaimed > 0 && credits >= 10000) {
      return {
        action: 'claim_planet',
        turnsToSpend: 1,
        priority: 85,
        reason: 'warrior_claiming'
      }
    }
    
    // Patrol for combat opportunities
    if (turns >= 10 && warps > 0) {
      return {
        action: 'patrol',
        turnsToSpend: Math.min(turns, 30),
        priority: 80,
        reason: 'warrior_patrolling'
      }
    }
    
    // Emergency trading for credits
    if (credits < 1000 && ports.commodity > 0) {
      return {
        action: 'emergency_trade',
        turnsToSpend: Math.min(turns, 10),
        priority: 75,
        reason: 'warrior_emergency'
      }
    }
    
    return {
      action: 'wait',
      turnsToSpend: 0,
      priority: 0,
      reason: 'warrior_no_turns'
    }
  }
}

class ColonizerPersonality implements AIPersonality {
  type = 'Colonizer'
  private aiService: AIService
  
  constructor(aiService: AIService) {
    this.aiService = aiService
  }
  
  makeDecision(situation: any): AIDecision {
    const { turns, credits, ports, planets, warps, hull, cargo, shipLevels } = situation
    
    // Check combat readiness and tech level
    const combatStatus = this.aiService.checkCombatReadiness(situation)
    const techStatus = this.aiService.checkTechLevel(situation)
    
    // CRITICAL: Return to sector 0 if combat supplies below 50%
    if (combatStatus.needsRefill && ports.special === 0 && turns >= 1) {
      return {
        action: 'hyperspace',
        turnsToSpend: 1,
        priority: 97,
        reason: 'colonizer_refill_combat_supplies'
      }
    }
    
    // Combat supplies auto-regenerate now - no need to purchase
    
    // CRITICAL: Hoarding credits with low tech - MUST UPGRADE
    if (techStatus.isHoarding && ports.special > 0) {
      return {
        action: 'upgrade_ship',
        turnsToSpend: Math.min(turns, 20),
        priority: 99,
        reason: 'colonizer_stop_hoarding'
      }
    }
    
    // Seek special port if hoarding
    if (techStatus.isHoarding && ports.special === 0 && turns >= 1) {
      return {
        action: 'hyperspace',
        turnsToSpend: 1,
        priority: 98,
        reason: 'colonizer_seek_upgrades'
      }
    }
    
    // Claim planets - highest priority
    if (planets.unclaimed > 0 && credits >= 10000) {
      return {
        action: 'claim_planet',
        turnsToSpend: 1,
        priority: 95,
        reason: 'colonizer_claiming'
      }
    }
    
    // Develop planets
    if (turns >= 5 && planets.total > 0) {
      return {
        action: 'develop_planets',
        turnsToSpend: Math.min(turns, 25),
        priority: 85,
        reason: 'colonizer_developing'
      }
    }
    
    // Ship upgrades for better planet management
    if (credits >= 2000 && ports.special > 0) {
      return {
        action: 'upgrade_ship',
        turnsToSpend: Math.min(turns, 15),
        priority: 90,
        reason: 'colonizer_upgrading'
      }
    }
    
    // Seek special port for upgrades
    if (credits >= 2000 && ports.special === 0 && turns >= 3) {
      return {
        action: 'hyperspace',
        turnsToSpend: 1,
        priority: 88,
        reason: 'colonizer_seeking_special_port'
      }
    }
    
    // Explore to find new planets
    if (turns >= 5 && warps > 0) {
      return {
        action: 'explore',
        turnsToSpend: Math.min(turns, 20),
        priority: 75,
        reason: 'colonizer_seeking'
      }
    }
    
    return {
      action: 'wait',
      turnsToSpend: 0,
      priority: 0,
      reason: 'colonizer_no_turns'
    }
  }
}

class BalancedPersonality implements AIPersonality {
  type = 'Balanced'
  private aiService: AIService
  
  constructor(aiService: AIService) {
    this.aiService = aiService
  }
  
  makeDecision(situation: any): AIDecision {
    const { turns, credits, ports, planets, warps, hull, cargo, shipLevels } = situation
    // Energy does not take cargo space
    const cargoTotal = (cargo?.ore || 0) + (cargo?.organics || 0) + (cargo?.goods || 0)
    
    // Check combat readiness and tech level
    const combatStatus = this.aiService.checkCombatReadiness(situation)
    const techStatus = this.aiService.checkTechLevel(situation)
    
    // CRITICAL: Return to sector 0 if combat supplies below 50%
    if (combatStatus.needsRefill && ports.special === 0 && turns >= 1) {
      return {
        action: 'hyperspace',
        turnsToSpend: 1,
        priority: 97,
        reason: 'balanced_refill_combat_supplies'
      }
    }
    
    // Combat supplies auto-regenerate now - no need to purchase
    
    // CRITICAL: Hoarding credits with low tech - MUST UPGRADE
    if (techStatus.isHoarding && ports.special > 0) {
      return {
        action: 'upgrade_ship',
        turnsToSpend: Math.min(turns, 20),
        priority: 99,
        reason: 'balanced_stop_hoarding'
      }
    }
    
    // Seek special port if hoarding
    if (techStatus.isHoarding && ports.special === 0 && turns >= 1) {
      return {
        action: 'hyperspace',
        turnsToSpend: 1,
        priority: 98,
        reason: 'balanced_seek_upgrades'
      }
    }
    
    // Emergency trading - only if we have cargo to sell or ports to trade at
    if (credits < 500 && (cargoTotal > 10 || ports.commodity > 0)) {
      return {
        action: 'emergency_trade',
        turnsToSpend: Math.min(turns, 15),
        priority: 100,
        reason: 'balanced_emergency'
      }
    }
    
    // Claim planets
    if (planets.unclaimed > 0 && credits >= 10000) {
      return {
        action: 'claim_planet',
        turnsToSpend: 1,
        priority: 80,
        reason: 'balanced_claiming'
      }
    }
    
    // Trade routes - be more aggressive with turn spending
    if (turns >= 10 && ports.commodity > 0) {
      return {
        action: 'trade_route',
        turnsToSpend: Math.min(turns, 30),
        priority: 75,
        reason: 'balanced_trading'
      }
    }
    
    // Ship upgrades - balanced approach (HIGH PRIORITY!)
    if (credits >= 2000 && ports.special > 0) {
      return {
        action: 'upgrade_ship',
        turnsToSpend: Math.min(turns, 15),
        priority: 92,
        reason: 'balanced_upgrading'
      }
    }
    
    // Seek special port for upgrades
    if (credits >= 2000 && ports.special === 0 && turns >= 3) {
      return {
        action: 'hyperspace',
        turnsToSpend: 1,
        priority: 90,
        reason: 'balanced_seeking_special_port'
      }
    }
    
    // Exploration - be more aggressive
    if (turns >= 5 && warps > 0) {
      return {
        action: 'explore',
        turnsToSpend: Math.min(turns, 20),
        priority: 60,
        reason: 'balanced_exploring'
      }
    }
    
    // If we have turns but no clear action, explore anyway
    if (turns > 0) {
      return {
        action: 'explore',
        turnsToSpend: Math.min(turns, 10),
        priority: 50,
        reason: 'balanced_default_explore'
      }
    }
    
    return {
      action: 'wait',
      turnsToSpend: 0,
      priority: 0,
      reason: 'balanced_no_turns'
    }
  }
}