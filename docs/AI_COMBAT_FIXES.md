# AI Combat System Improvements

## Problem
AI players were not upgrading combat-related equipment (sensors, beam weapons, torpedo launchers, cloak) and were not purchasing fighters, torpedoes, and armor points at special ports. They were also sitting on massive credit reserves without upgrading, and not maintaining combat supplies. This made them sitting ducks in combat situations.

## Solution (Updated Oct 13, 2025)

### 1. Enhanced Upgrade System (`lib/ai-service.ts`)

#### Changed Upgrade Priority Order
**Old Priority:**
```
hull -> engine -> computer -> power -> sensors -> beam -> shields -> torp_launcher -> armor -> cloak
```

**New Priority:**
```
sensors -> beam -> torp_launcher -> cloak -> shields -> armor -> hull -> engine -> computer -> power
```

Combat-focused upgrades now come first!

#### Improved Upgrade Logic
- **Old:** Stopped upgrading on first failure (likely when one system maxed out or credits ran low)
- **New:** Tries all upgrade types in sequence, only stopping after failing on ALL systems (full cycle)
- **Result:** AI will upgrade multiple systems instead of just one or two

#### Added Combat Equipment Purchases
After upgrading ship levels, AI now automatically purchases **TO MAXIMUM CAPACITY**:
- **Fighters:** 100% of capacity (100 * 1.5^(comp_lvl - 1))
  - Always buys to full capacity when at special port
  - Only requires enough credits for the purchase
  
- **Torpedoes:** 100% of capacity (torp_launcher_lvl * 100)
  - Always buys to full capacity when at special port
  - Only requires enough credits for the purchase
  
- **Armor Points:** 100% of capacity (100 * 1.5^armor_lvl)
  - Always buys to full capacity when at special port
  - Only requires enough credits for the purchase

This ensures AI players are always at full combat strength after visiting a special port.

### 2. More Aggressive Upgrade Behavior

#### Lowered Credit Thresholds
All AI personality types now seek upgrades at lower credit levels:

**Trader Personality:**
- Old threshold: 5,000 credits
- New threshold: 2,000 credits
- Upgrade turns: 10 → 15

**Warrior Personality:**
- Old threshold: 3,000 credits
- New threshold: 1,500 credits
- Upgrade turns: 15 → 20 (most aggressive)

**Colonizer Personality:**
- Old threshold: 4,000 credits
- New threshold: 2,000 credits
- Upgrade turns: 10 → 15

**Balanced Personality:**
- Old threshold: 5,000 credits
- New threshold: 2,000 credits
- Upgrade turns: 10 → 15

### 3. Improved Communism Boost

When giving struggling AI players credit boosts, the system now:
- Prioritizes combat upgrades first (sensors, beam, torp_launcher, cloak, shields, armor)
- Attempts 10 upgrade cycles instead of just 4
- Tries all upgrade types instead of stopping early

### 3. Combat Supply Management

#### Automatic Refill System
AI players now actively monitor their combat supplies:
- **50% Threshold:** If fighters, torpedoes, or armor drop below 50% capacity
- **Immediate Action:** Hyperspace to sector 0 to refill at special port
- **High Priority:** Priority 97-99 (overrides most other actions)
- **All Personalities:** Even traders and explorers maintain combat readiness

### 4. Anti-Hoarding System

#### Tech Level Monitoring
New system prevents AI from sitting on huge credits with low tech:
- **Average Tech Calculation:** Monitors average level across all 10 systems
- **Expected Cost Formula:** `1000 * 2^(average_level)` (accounts for doubling costs)
- **Hoarding Detection:** Triggers when credits > 50x expected upgrade cost AND avg level < 15
- **Forced Upgrades:** Priority 99-100 action to spend credits on upgrades

Example: If average tech level is 5, expected cost is 32,000 credits
- Hoarding threshold: 1.6 million credits
- AI will be forced to hyperspace to sector 0 and upgrade until no longer hoarding

### 5. Personality-Based Upgrade Priorities

Each personality type now has customized upgrade order:

**Warriors:** Combat-first approach
```
beam → torp_launcher → shields → computer → sensors → cloak → armor → hull → engine → power
```

**Traders & Colonizers:** Economy-first approach  
```
hull → engine → computer → power → sensors → beam → shields → torp_launcher → armor → cloak
```

**Balanced & Explorer:** Mixed approach
```
sensors → hull → beam → engine → torp_launcher → computer → shields → armor → cloak → power
```

This ensures each personality develops according to their role while still maintaining all systems.

## Expected Results

1. **Better Combat Readiness:** AI players will have upgraded weapons, sensors, and defenses
2. **Full Equipment:** AI ships will ALWAYS carry max fighters, torpedoes, and armor
3. **Active Supply Management:** AI will return to sector 0 when supplies drop below 50%
4. **No Credit Hoarding:** AI won't sit on 500M credits with level 5 tech
5. **Earlier Upgrades:** AI will start upgrading at 2,000 credits instead of waiting for 5,000+
6. **Balanced Development:** All ship systems will be upgraded across the board
7. **Personality-Appropriate Growth:** Warriors prioritize weapons, traders prioritize hull
8. **Tougher Opponents:** AI players will be actual threats in combat, not easy targets

## Testing

To verify the changes are working:
1. Check AI player ship stats in the admin panel
2. Look for:
   - Non-zero sensor levels
   - Non-zero beam weapon levels
   - Non-zero torpedo launcher levels
   - Non-zero cloak levels
   - Fighters in inventory
   - Torpedoes in inventory
   - Armor points present

## Technical Details

### Functions Modified
- `executeUpgradeShip()` - Complete rewrite with personality-based priorities
- `applyCommunismBoost()` - Updated upgrade sequence to prioritize combat
- `analyzeSituation()` - Enhanced to include ship levels and combat supplies
- `checkCombatReadiness()` - NEW: Helper to detect low combat supplies
- `checkTechLevel()` - NEW: Helper to detect credit hoarding
- `TraderPersonality.makeDecision()` - Added combat readiness and anti-hoarding checks
- `WarriorPersonality.makeDecision()` - Added combat readiness (highest priority) and anti-hoarding
- `ColonizerPersonality.makeDecision()` - Added combat readiness and anti-hoarding
- `BalancedPersonality.makeDecision()` - Added combat readiness and anti-hoarding
- `ExplorerPersonality.makeDecision()` - Added combat readiness and anti-hoarding

### New Features
- **Max-buy system:** Always purchases to 100% capacity at special ports
- **Combat readiness monitoring:** Checks fighter/torpedo/armor levels every decision
- **Automatic refill:** Hyperspace to sector 0 when below 50% capacity
- **Anti-hoarding:** Detects excessive credits with low tech and forces upgrades
- **Personality-based upgrades:** Different upgrade order per personality type
- **Smart tech level calculation:** Average across all 10 ship systems
- **Exponential cost awareness:** Accounts for doubling upgrade costs
- **Non-fatal error handling:** Purchases won't crash upgrade process

### Database Functions Used
- `game_ship_upgrade()` - For upgrading ship systems
- `purchase_special_port_items()` - For buying fighters/torpedoes/armor to max capacity
- `game_hyperspace()` - For emergency return to sector 0

### Key Thresholds
- **Combat Refill:** < 50% on any combat supply → Hyperspace to sector 0
- **Hoarding Detection:** Credits > 50x expected upgrade cost AND avg tech < 15
- **Upgrade Threshold:** 
  - Warriors: 1,500 credits
  - Others: 2,000 credits
- **Expected Upgrade Cost:** `1000 * 2^(floor(avgLevel))`

### Priority Levels
- 100: Emergency (hoarding detection for Warriors)
- 99: Critical hoarding/combat refill
- 98: Seeking upgrades when hoarding
- 97: Combat refill (non-Warriors)
- 95-96: Normal upgrades
- 90-93: Seeking special port for upgrades
- 70-85: Trading, exploration, planet claiming
- 0: Wait (no turns)

## Date
October 13, 2025

