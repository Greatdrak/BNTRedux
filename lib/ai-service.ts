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
        return new TraderPersonality()
      case 'Explorer':
        return new ExplorerPersonality()
      case 'Warrior':
        return new WarriorPersonality()
      case 'Colonizer':
        return new ColonizerPersonality()
      default:
        return new BalancedPersonality()
    }
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
            id, credits, hull, hull_max, ore, organics, goods, energy
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
      
      // Get ship levels separately
      const { data: shipLevelsData } = await supabaseAdmin
        .from('ship_levels')
        .select('hull_level, engine_level, power_level, computer_level')
        .eq('ship_id', ship.id)
        .single()
      
      const shipLevels = shipLevelsData || { hull_level: 0, engine_level: 0, power_level: 0, computer_level: 0 }
      
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
        console.log(`⚠️ Sector 0 has no special port!`, { portCount, commodityPorts, specialPorts })
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
        hullLevel: shipLevels?.hull_level || 0,
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
    
    let successfulUpgrades = 0
    let turnsUsed = 0
    const errors: string[] = []
    
    // Upgrade priority: hull, engine, computer, power, sensors, weapons, shields
    const upgradeOrder = ['hull', 'engine', 'computer', 'power', 'sensors', 'beam', 'shields', 'torp_launcher', 'armor', 'cloak']
    
    // Spend multiple turns upgrading different systems
    for (let i = 0; i < Math.min(turnsToSpend, 10); i++) {
      const upgradeType = upgradeOrder[i % upgradeOrder.length]
      
      const { data: result, error: upgradeError } = await supabaseAdmin.rpc('game_ship_upgrade', {
        p_user_id: userId,
        p_attr: upgradeType,
        p_universe_id: universeId
      })
      
      if (!upgradeError && result?.success) {
        successfulUpgrades++
        turnsUsed++
      } else if (upgradeError) {
        // Stop if we get an error (likely out of credits or max level)
        errors.push(upgradeError.message)
        break
      } else {
        // Stop if upgrade fails (likely out of credits)
        break
      }
      
      // Small delay to prevent overload
      await new Promise(resolve => setTimeout(resolve, 50))
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
  
  private async executeExplore(userId: string, sectorId: string, turnsToSpend: number, universeId: string) {
    // Simple exploration
    return this.executeDeepExploration(userId, sectorId, Math.min(turnsToSpend, 10), universeId)
  }
  
  // Communism boost system - help AI players catch up when human players are far ahead
  async applyCommunismBoost(universeId: string): Promise<any> {
    try {
      // Refresh scores first to ensure they're up to date
      try {
        await supabaseAdmin.rpc('refresh_all_player_scores', { p_universe_id: universeId })
      } catch (e) {
        console.warn('Score refresh in communism boost failed', e)
      }

      // Get all human scores to compute averages/percentiles
      const { data: humanPlayers, error: humanError } = await supabaseAdmin
        .from('players')
        .select('score')
        .eq('universe_id', universeId)
        .eq('is_ai', false)
        .order('score', { ascending: false })
      
      if (humanError || !humanPlayers || humanPlayers.length === 0) {
        return { success: false, message: 'No human players found' }
      }

      // Compute aggregates
      const humanScores = humanPlayers.map(p => p.score || 0)
      const humanTop = humanScores[0] || 0
      const humanAvg = humanScores.reduce((a, b) => a + b, 0) / humanScores.length
      const humanP75 = humanScores[Math.max(0, Math.floor(humanScores.length * 0.25) - 1)] || humanTop
      
      // Calculate median human score (avoids skew from brand new players)
      const midIndex = Math.floor(humanScores.length / 2)
      const humanMedian = humanScores.length % 2 === 0 
        ? Math.floor((humanScores[midIndex - 1] + humanScores[midIndex]) / 2)
        : humanScores[midIndex]
      
      // Target: AI should reach 80% of median human player
      const targetAIScore = Math.floor(humanMedian * 0.80)

      // Get all AI scores to derive distribution/ranks
      const { data: aiPlayersAll, error: aiError } = await supabaseAdmin
        .from('players')
        .select('id, score')
        .eq('universe_id', universeId)
        .eq('is_ai', true)
        .order('score', { ascending: false })
      
      if (aiError || !aiPlayersAll || aiPlayersAll.length === 0) {
        return { success: false, message: 'No AI players found' }
      }

      const topAIScore = aiPlayersAll[0].score || 0
      const scoreGap = Math.max(0, humanTop - topAIScore)
      
      // Calculate minimum boost needed to get struggling AIs to target (80% of lowest human)
      // Score formula: (ship_tech_value + credits + planet_value + exploration) / 100
      // So: targetScore * 100 = raw value needed
      // We give credits which convert to both ship upgrades AND direct score
      // Conservative: give 50% of needed value as pure credits (rest from trading/upgrades)
      const minBoostPerAI = Math.floor((targetAIScore * 100) * 0.50) // 50% of score gap as credits

      // Trigger when top human significantly outpaces AI ecosystem
      const boostThreshold = Math.max(Math.floor(humanAvg * 0.15), 10000)

      // Communism boost analysis (minimal logging)

      // Check if AIs have surpassed humans - if so, apply nerf to overpowered AIs
      if (topAIScore >= humanMedian) {
        // Find AIs that are too powerful (above human median) and nerf them
        const overpoweredAIs = aiPlayersAll.filter(ai => (ai.score || 0) > humanMedian)
        
        if (overpoweredAIs.length > 0) {
          
          for (const ai of overpoweredAIs) {
            // Reduce credits to bring them back in line (target 70% of median)
            const targetCredits = Math.floor(humanMedian * 70) // Conservative target
            
            const { error: nerfError } = await supabaseAdmin
              .from('ships')
              .update({ credits: targetCredits })
              .eq('player_id', ai.id)
            
            if (!nerfError) {
              console.log(`  Nerfed ${ai.id}: reduced credits to ${targetCredits}`)
            }
          }
        }
        
        return {
          success: true,
          message: `AI players at/above median - nerfed ${overpoweredAIs.length} AIs`,
          humanTop,
          humanMedian,
          targetAIScore,
          humanAvg,
          scoreGap: 0,
          nerfedAIs: overpoweredAIs.length,
          boostThreshold
        }
      }

      if (scoreGap > boostThreshold) {
        // MASSIVELY aggressive boost to account for exponential score scaling
        // Pool = MAX of: 200% of score gap OR enough to get all AIs to target
        const dynamicPool = Math.max(
          Math.floor(scoreGap * 2.00), 
          minBoostPerAI * aiPlayersAll.length,
          500000
        )
        
        // Get all AI players with low scores
        const { data: strugglingAIs, error: strugglingError } = await supabaseAdmin
          .from('players')
          .select(`
            id, handle, score, user_id,
            ships!inner(credits, hull)
          `)
          .eq('universe_id', universeId)
          .eq('is_ai', true)
          .lt('score', Math.max(topAIScore * 0.95, humanAvg * 0.40)) // widen eligibility: below 95% of top AI or 40% of human avg
        
        if (strugglingError || !strugglingAIs || strugglingAIs.length === 0) {
          return { success: false, message: 'No struggling AI players found' }
        }
        
        let boostedPlayers = 0
        const boostResults = []
        
        for (let idx = 0; idx < strugglingAIs.length; idx++) {
          const player = strugglingAIs[idx]
          const ship = Array.isArray(player.ships) ? player.ships[0] : player.ships
          const currentCredits = ship.credits || 0
          // Player-relative multiplier: worse rank -> larger share
          const rankFactor = 1 - (idx / Math.max(1, strugglingAIs.length - 1)) // 1..~0 (worst gets highest)
          // Scale per-player top-up by low hull (helps jump upgrade costs)
          const hull = ship.hull || 0
          const hullFactor = 1 + Math.max(0, 15 - hull) * 0.15 // even stronger hull boost for low levels
          // Give each AI a much larger share - they need 10k-30k per upgrade
          const perPlayerBoost = Math.floor(dynamicPool * (0.30 + 0.40 * rankFactor) * hullFactor)
          const newCredits = currentCredits + perPlayerBoost
          
          // Update AI player's credits
          const { error: updateError } = await supabaseAdmin
            .from('ships')
            .update({ credits: newCredits })
            .eq('player_id', player.id)
          
          if (!updateError) {
            boostedPlayers++
            boostResults.push({
              player: player.handle,
              oldCredits: currentCredits,
              newCredits: newCredits,
              boostAmount: perPlayerBoost
            })

            // Attempt to convert credits to assets via upgrades right away
            // Try multiple upgrades to spend the boost on tech
            for (let u = 0; u < 5; u++) {
              // Prioritize hull for score
              const { data: hullData, error: hullErr } = await supabaseAdmin.rpc('game_ship_upgrade', {
                p_user_id: player.user_id,
                p_attr: 'hull',
                p_universe_id: universeId
              })
              if (hullErr || (hullData && hullData.error)) break
              
              // Then engine for movement
              const { data: engineData, error: engineErr } = await supabaseAdmin.rpc('game_ship_upgrade', {
                p_user_id: player.user_id,
                p_attr: 'engine',
                p_universe_id: universeId
              })
              if (engineErr || (engineData && engineData.error)) {}
              
              // Then computer for trading capacity
              const { data: compData, error: compErr } = await supabaseAdmin.rpc('game_ship_upgrade', {
                p_user_id: player.user_id,
                p_attr: 'computer',
                p_universe_id: universeId
              })
              if (compErr || (compData && compData.error)) {}
              
              // Then power for energy
              const { data: powerData, error: powerErr } = await supabaseAdmin.rpc('game_ship_upgrade', {
                p_user_id: player.user_id,
                p_attr: 'power',
                p_universe_id: universeId
              })
              if (powerErr || (powerData && powerData.error)) {}
            }
          }
        }
        
        return {
          success: true,
          message: `Applied communism boost to ${boostedPlayers} AI players`,
          humanTop,
          humanMedian,
          targetAIScore,
          humanAvg,
          scoreGap,
          dynamicPool,
          minBoostPerAI,
          boostedPlayers,
          boostResults
        }
      }
      
      return {
        success: true,
        message: 'No boost needed - AI players are competitive',
        humanTop,
        humanMedian,
        targetAIScore,
        humanAvg,
        scoreGap,
        boostThreshold
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
            console.log(`Error processing AI player ${player.handle}:`, error)
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
        topPlayers: topAIPlayers || [],
        debug: {
          samplePlayer: aiPlayers[0],
          samplePlayerTurns: aiPlayers[0]?.turns
        }
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
  
  makeDecision(situation: any): AIDecision {
    const { turns, credits, ports, planets, warps, hull, cargo } = situation
    // Energy does not take cargo space
    const cargoTotal = (cargo?.ore || 0) + (cargo?.organics || 0) + (cargo?.goods || 0)
    
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
    if (credits >= 5000 && ports.special > 0) {
      return {
        action: 'upgrade_ship',
        turnsToSpend: Math.min(turns, 10), // Spend lots of turns upgrading
        priority: 95, // Higher priority than trading!
        reason: 'trader_upgrading'
      }
    }
    
    // CRITICAL: Seek special port for upgrades if we have lots of credits
    if (credits >= 5000 && ports.special === 0 && turns >= 3) {
      return {
        action: 'explore',
        turnsToSpend: Math.min(turns, 10),
        priority: 93, // Very high priority - must find special port!
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
  
  makeDecision(situation: any): AIDecision {
    const { turns, credits, ports, planets, warps, hull, cargo } = situation
    
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
  
  makeDecision(situation: any): AIDecision {
    const { turns, credits, ports, planets, warps, hull, cargo } = situation
    
    // Ship upgrades for combat - warriors prioritize this ABOVE ALL!
    if (credits >= 3000 && ports.special > 0) {
      return {
        action: 'upgrade_ship',
        turnsToSpend: Math.min(turns, 15), // Warriors upgrade VERY aggressively
        priority: 98, // Highest priority!
        reason: 'warrior_upgrading'
      }
    }
    
    // Seek special port for upgrades - CRITICAL
    if (credits >= 3000 && ports.special === 0 && turns >= 3) {
      return {
        action: 'explore',
        turnsToSpend: Math.min(turns, 12),
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
  
  makeDecision(situation: any): AIDecision {
    const { turns, credits, ports, planets, warps, hull, cargo } = situation
    
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
    if (credits >= 4000 && ports.special > 0) {
      return {
        action: 'upgrade_ship',
        turnsToSpend: Math.min(turns, 10),
        priority: 90,
        reason: 'colonizer_upgrading'
      }
    }
    
    // Seek special port for upgrades
    if (credits >= 4000 && ports.special === 0 && turns >= 3) {
      return {
        action: 'explore',
        turnsToSpend: Math.min(turns, 8),
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
  
  makeDecision(situation: any): AIDecision {
    const { turns, credits, ports, planets, warps, hull, cargo } = situation
    // Energy does not take cargo space
    const cargoTotal = (cargo?.ore || 0) + (cargo?.organics || 0) + (cargo?.goods || 0)
    
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
    if (credits >= 5000 && ports.special > 0) {
      return {
        action: 'upgrade_ship',
        turnsToSpend: Math.min(turns, 10),
        priority: 92,
        reason: 'balanced_upgrading'
      }
    }
    
    // Seek special port for upgrades
    if (credits >= 5000 && ports.special === 0 && turns >= 3) {
      return {
        action: 'explore',
        turnsToSpend: Math.min(turns, 10),
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