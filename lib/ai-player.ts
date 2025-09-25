// AI Player System
// Handles AI player decision making and actions

export interface AIPlayer {
  id: string
  name: string
  credits: number
  sectorId: string
  sectorNumber: number
  cargo: {
    ore: number
    organics: number
    goods: number
    energy: number
    colonists: number
  }
  shipLevels: {
    hull: number
    engine: number
    power: number
    computer: number
    sensors: number
    beamWeapon: number
    armor: number
    cloak: number
    torpLauncher: number
    shield: number
  }
  fighters: number
  torpedoes: number
  armorPoints: number
  turns: number
}

export interface AIDecision {
  action: 'trade' | 'move' | 'upgrade' | 'claim_planet' | 'explore'
  priority: number
  reasoning: string
  expectedProfit?: number
  targetSector?: number
  targetResource?: string
  targetUpgrade?: string
}

export interface MarketData {
  sectorNumber: number
  port?: {
    kind: string
    prices: {
      ore: number
      organics: number
      goods: number
      energy: number
    }
    stock: {
      ore: number
      organics: number
      goods: number
      energy: number
    }
  }
  planets: Array<{
    id: string
    name: string
    owner: boolean
    ownerName?: string
  }>
}

export class AIPlayerManager {
  private aiPlayers: AIPlayer[] = []
  private marketData: MarketData[] = []

  constructor() {
    // Initialize AI players and market data
  }

  // Main AI decision making function
  async makeDecisions(): Promise<AIDecision[]> {
    const decisions: AIDecision[] = []

    for (const aiPlayer of this.aiPlayers) {
      const decision = await this.evaluatePlayerSituation(aiPlayer)
      if (decision) {
        decisions.push(decision)
      }
    }

    return decisions
  }

  // Evaluate what an AI player should do
  private async evaluatePlayerSituation(player: AIPlayer): Promise<AIDecision | null> {
    const decisions: AIDecision[] = []

    // 1. Check for profitable trading opportunities
    const tradeDecision = this.evaluateTrading(player)
    if (tradeDecision) decisions.push(tradeDecision)

    // 2. Check for ship upgrade opportunities
    const upgradeDecision = this.evaluateUpgrades(player)
    if (upgradeDecision) decisions.push(upgradeDecision)

    // 3. Check for planet claiming opportunities
    const planetDecision = this.evaluatePlanetClaiming(player)
    if (planetDecision) decisions.push(planetDecision)

    // 4. Check for exploration opportunities
    const exploreDecision = this.evaluateExploration(player)
    if (exploreDecision) decisions.push(exploreDecision)

    // Return highest priority decision
    if (decisions.length === 0) return null
    
    return decisions.sort((a, b) => b.priority - a.priority)[0]
  }

  // Evaluate trading opportunities
  private evaluateTrading(player: AIPlayer): AIDecision | null {
    const currentSector = this.marketData.find(s => s.sectorNumber === player.sectorNumber)
    if (!currentSector?.port) return null

    const port = currentSector.port
    let bestTrade: AIDecision | null = null
    let maxProfit = 0

    // Check each resource for trading opportunities
    const resources = ['ore', 'organics', 'goods', 'energy'] as const
    
    for (const resource of resources) {
      const currentPrice = port.prices[resource]
      const currentStock = port.stock[resource]
      const playerCargo = player.cargo[resource]

      // Look for profitable sell opportunities
      if (playerCargo > 0) {
        // Find sectors with higher prices for this resource
        const profitableSectors = this.marketData.filter(sector => 
          sector.port && 
          sector.port.prices[resource] > currentPrice * 1.1 && // 10% profit margin
          sector.sectorNumber !== player.sectorNumber
        )

        if (profitableSectors.length > 0) {
          const targetSector = profitableSectors[0]
          const profit = (targetSector.port!.prices[resource] - currentPrice) * playerCargo
          
          if (profit > maxProfit) {
            maxProfit = profit
            bestTrade = {
              action: 'move',
              priority: Math.min(8, Math.floor(profit / 1000) + 3),
              reasoning: `Profitable trade: ${resource} at sector ${targetSector.sectorNumber} (+${profit} credits)`,
              expectedProfit: profit,
              targetSector: targetSector.sectorNumber,
              targetResource: resource
            }
          }
        }
      }

      // Look for profitable buy opportunities
      if (player.credits > currentPrice * 10 && currentStock > 0) {
        // Find sectors with lower prices for this resource
        const cheapSectors = this.marketData.filter(sector => 
          sector.port && 
          sector.port.prices[resource] < currentPrice * 0.9 && // 10% discount
          sector.sectorNumber !== player.sectorNumber
        )

        if (cheapSectors.length > 0) {
          const targetSector = cheapSectors[0]
          const profit = (currentPrice - targetSector.port!.prices[resource]) * Math.min(10, currentStock)
          
          if (profit > maxProfit) {
            maxProfit = profit
            bestTrade = {
              action: 'move',
              priority: Math.min(7, Math.floor(profit / 1000) + 2),
              reasoning: `Buy low, sell high: ${resource} at sector ${targetSector.sectorNumber} (+${profit} credits)`,
              expectedProfit: profit,
              targetSector: targetSector.sectorNumber,
              targetResource: resource
            }
          }
        }
      }
    }

    return bestTrade
  }

  // Evaluate ship upgrade opportunities
  private evaluateUpgrades(player: AIPlayer): AIDecision | null {
    const upgrades = [
      { type: 'hull', cost: 1000, benefit: 'More cargo space' },
      { type: 'engine', cost: 1000, benefit: 'Faster movement' },
      { type: 'power', cost: 1000, benefit: 'More energy' },
      { type: 'computer', cost: 1000, benefit: 'More fighters' },
      { type: 'sensors', cost: 1000, benefit: 'Better scanning' },
      { type: 'beamWeapon', cost: 1000, benefit: 'Better combat' },
      { type: 'armor', cost: 1000, benefit: 'More armor points' },
      { type: 'cloak', cost: 1000, benefit: 'Stealth' },
      { type: 'torpLauncher', cost: 1000, benefit: 'More torpedoes' },
      { type: 'shield', cost: 1000, benefit: 'Better shields' }
    ]

    for (const upgrade of upgrades) {
      if (player.credits >= upgrade.cost) {
        const currentLevel = player.shipLevels[upgrade.type as keyof typeof player.shipLevels]
        
        // Prioritize upgrades based on current level and needs
        let priority = 3
        if (currentLevel < 3) priority = 5 // Low levels are important
        if (upgrade.type === 'hull' && this.getCargoSpace(player) < 50) priority = 7 // Need cargo space
        if (upgrade.type === 'engine' && currentLevel < 2) priority = 6 // Need speed
        
        return {
          action: 'upgrade',
          priority,
          reasoning: `Upgrade ${upgrade.type}: ${upgrade.benefit}`,
          targetUpgrade: upgrade.type
        }
      }
    }

    return null
  }

  // Evaluate planet claiming opportunities
  private evaluatePlanetClaiming(player: AIPlayer): AIDecision | null {
    const currentSector = this.marketData.find(s => s.sectorNumber === player.sectorNumber)
    if (!currentSector) return null

    const unclaimedPlanets = currentSector.planets.filter(p => !p.owner)
    
    if (unclaimedPlanets.length > 0 && player.credits >= 10000) {
      return {
        action: 'claim_planet',
        priority: 6,
        reasoning: `Claim unclaimed planet: ${unclaimedPlanets[0].name}`,
        expectedProfit: 0 // Long-term investment
      }
    }

    return null
  }

  // Evaluate exploration opportunities
  private evaluateExploration(player: AIPlayer): AIDecision | null {
    // Simple exploration: move to random sectors
    const knownSectors = this.marketData.map(s => s.sectorNumber)
    const randomSector = Math.floor(Math.random() * 500) + 1
    
    if (!knownSectors.includes(randomSector)) {
      return {
        action: 'explore',
        priority: 2,
        reasoning: `Explore new sector: ${randomSector}`,
        targetSector: randomSector
      }
    }

    return null
  }

  // Helper function to calculate cargo space
  private getCargoSpace(player: AIPlayer): number {
    return player.shipLevels.hull * 10 // Simplified calculation
  }

  // Update AI player data
  async updateAIPlayer(playerId: string, updates: Partial<AIPlayer>): Promise<void> {
    const index = this.aiPlayers.findIndex(p => p.id === playerId)
    if (index !== -1) {
      this.aiPlayers[index] = { ...this.aiPlayers[index], ...updates }
    }
  }

  // Update market data
  async updateMarketData(data: MarketData[]): Promise<void> {
    this.marketData = data
  }
}

export default AIPlayerManager

