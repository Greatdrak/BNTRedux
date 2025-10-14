// Simple sound system for the game
class SoundSystem {
  private backgroundMusic: HTMLAudioElement | null = null
  private musicEnabled: boolean = true
  private soundEffectsEnabled: boolean = true

  constructor() {
    // Only initialize in browser
    if (typeof window === 'undefined') return

    // Load background music
    this.backgroundMusic = new Audio('/sounds/DancingStars.mp3')
    this.backgroundMusic.loop = true
    this.backgroundMusic.volume = 0.15 // Reduced volume to 15%

    // Load settings from localStorage
    // Default to false so user must explicitly enable it (due to browser autoplay policy)
    this.musicEnabled = localStorage.getItem('musicEnabled') === 'true'
    this.soundEffectsEnabled = localStorage.getItem('soundEffectsEnabled') !== 'false'

    // Don't autoplay - browsers block it. User must interact first.
    // Music will start when user toggles it on
  }

  // Background music controls
  toggleMusic() {
    if (typeof window === 'undefined') return

    this.musicEnabled = !this.musicEnabled
    localStorage.setItem('musicEnabled', this.musicEnabled.toString())
    
    if (this.musicEnabled) {
      // User interaction allows us to start playback
      this.playBackgroundMusic()
    } else {
      this.stopBackgroundMusic()
    }
  }

  // Initialize music on first user interaction (for autoplay policy)
  initMusic() {
    if (typeof window === 'undefined') return
    
    if (this.musicEnabled && this.backgroundMusic) {
      this.playBackgroundMusic()
    }
  }

  playBackgroundMusic() {
    if (this.backgroundMusic && this.musicEnabled) {
      this.backgroundMusic.play().catch((error) => {
        // Autoplay was blocked - this is expected on page load
        // User will need to click the music button to start playback
        console.log('Music autoplay blocked (expected) - click music button to start')
      })
    }
  }

  stopBackgroundMusic() {
    if (this.backgroundMusic) {
      this.backgroundMusic.pause()
      this.backgroundMusic.currentTime = 0
    }
  }

  // Sound effects
  playWarpSound() {
    if (typeof window === 'undefined' || !this.soundEffectsEnabled) return
    
    // Create a simple 2-bit warp sound using Web Audio API
    const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)()
    
    // Create oscillator for the warp sound
    const oscillator = audioContext.createOscillator()
    const gainNode = audioContext.createGain()
    
    oscillator.connect(gainNode)
    gainNode.connect(audioContext.destination)
    
    // Warp sound: descending frequency sweep
    oscillator.frequency.setValueAtTime(800, audioContext.currentTime)
    oscillator.frequency.exponentialRampToValueAtTime(200, audioContext.currentTime + 0.3)
    
    // Volume envelope
    gainNode.gain.setValueAtTime(0, audioContext.currentTime)
    gainNode.gain.linearRampToValueAtTime(0.3, audioContext.currentTime + 0.05)
    gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.3)
    
    oscillator.start(audioContext.currentTime)
    oscillator.stop(audioContext.currentTime + 0.3)
  }

  playClickSound() {
    if (typeof window === 'undefined' || !this.soundEffectsEnabled) return
    
    const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)()
    const oscillator = audioContext.createOscillator()
    const gainNode = audioContext.createGain()
    
    oscillator.connect(gainNode)
    gainNode.connect(audioContext.destination)
    
    // Click sound: short beep
    oscillator.frequency.setValueAtTime(1000, audioContext.currentTime)
    gainNode.gain.setValueAtTime(0.1, audioContext.currentTime)
    gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.1)
    
    oscillator.start(audioContext.currentTime)
    oscillator.stop(audioContext.currentTime + 0.1)
  }

  playSuccessSound() {
    if (typeof window === 'undefined' || !this.soundEffectsEnabled) return
    
    const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)()
    const oscillator = audioContext.createOscillator()
    const gainNode = audioContext.createGain()
    
    oscillator.connect(gainNode)
    gainNode.connect(audioContext.destination)
    
    // Success sound: ascending beep
    oscillator.frequency.setValueAtTime(600, audioContext.currentTime)
    oscillator.frequency.linearRampToValueAtTime(800, audioContext.currentTime + 0.2)
    gainNode.gain.setValueAtTime(0.2, audioContext.currentTime)
    gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.2)
    
    oscillator.start(audioContext.currentTime)
    oscillator.stop(audioContext.currentTime + 0.2)
  }

  playErrorSound() {
    if (typeof window === 'undefined' || !this.soundEffectsEnabled) return
    
    const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)()
    const oscillator = audioContext.createOscillator()
    const gainNode = audioContext.createGain()
    
    oscillator.connect(gainNode)
    gainNode.connect(audioContext.destination)
    
    // Error sound: descending beep
    oscillator.frequency.setValueAtTime(400, audioContext.currentTime)
    oscillator.frequency.linearRampToValueAtTime(200, audioContext.currentTime + 0.3)
    gainNode.gain.setValueAtTime(0.2, audioContext.currentTime)
    gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.3)
    
    oscillator.start(audioContext.currentTime)
    oscillator.stop(audioContext.currentTime + 0.3)
  }

  playScanSound() {
    if (typeof window === 'undefined' || !this.soundEffectsEnabled) return
    
    const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)()
    const oscillator = audioContext.createOscillator()
    const gainNode = audioContext.createGain()
    
    oscillator.connect(gainNode)
    gainNode.connect(audioContext.destination)
    
    // Scan sound: rapid ascending blip (like sonar ping)
    oscillator.type = 'sine'
    oscillator.frequency.setValueAtTime(600, audioContext.currentTime)
    oscillator.frequency.exponentialRampToValueAtTime(1200, audioContext.currentTime + 0.15)
    
    gainNode.gain.setValueAtTime(0, audioContext.currentTime)
    gainNode.gain.linearRampToValueAtTime(0.25, audioContext.currentTime + 0.02)
    gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.15)
    
    oscillator.start(audioContext.currentTime)
    oscillator.stop(audioContext.currentTime + 0.15)
  }

  playMapSound() {
    if (typeof window === 'undefined' || !this.soundEffectsEnabled) return
    
    const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)()
    
    // Create two oscillators for a richer sound
    const osc1 = audioContext.createOscillator()
    const osc2 = audioContext.createOscillator()
    const gainNode = audioContext.createGain()
    
    osc1.connect(gainNode)
    osc2.connect(gainNode)
    gainNode.connect(audioContext.destination)
    
    // Map sound: double beep (like opening a computer interface)
    osc1.type = 'square'
    osc2.type = 'square'
    
    osc1.frequency.setValueAtTime(800, audioContext.currentTime)
    osc2.frequency.setValueAtTime(1200, audioContext.currentTime)
    
    gainNode.gain.setValueAtTime(0.15, audioContext.currentTime)
    gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.1)
    
    osc1.start(audioContext.currentTime)
    osc2.start(audioContext.currentTime)
    osc1.stop(audioContext.currentTime + 0.1)
    osc2.stop(audioContext.currentTime + 0.1)
  }

  playHyperspaceSound() {
    if (typeof window === 'undefined' || !this.soundEffectsEnabled) return
    
    const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)()
    
    // Create white noise for whooshing effect
    const bufferSize = audioContext.sampleRate * 1.5 // 1.5 seconds
    const noiseBuffer = audioContext.createBuffer(1, bufferSize, audioContext.sampleRate)
    const output = noiseBuffer.getChannelData(0)
    
    // Generate filtered noise that sounds like wind/whoosh
    for (let i = 0; i < bufferSize; i++) {
      output[i] = Math.random() * 2 - 1
    }
    
    const whiteNoise = audioContext.createBufferSource()
    whiteNoise.buffer = noiseBuffer
    
    // Create filter to shape the noise
    const filter = audioContext.createBiquadFilter()
    filter.type = 'bandpass'
    filter.frequency.setValueAtTime(800, audioContext.currentTime)
    filter.frequency.exponentialRampToValueAtTime(200, audioContext.currentTime + 1.0)
    filter.Q.value = 1
    
    const gainNode = audioContext.createGain()
    
    whiteNoise.connect(filter)
    filter.connect(gainNode)
    gainNode.connect(audioContext.destination)
    
    // Envelope: fade in quickly, sustain, fade out
    gainNode.gain.setValueAtTime(0, audioContext.currentTime)
    gainNode.gain.linearRampToValueAtTime(0.3, audioContext.currentTime + 0.1)
    gainNode.gain.linearRampToValueAtTime(0.3, audioContext.currentTime + 0.8)
    gainNode.gain.linearRampToValueAtTime(0, audioContext.currentTime + 1.5)
    
    whiteNoise.start(audioContext.currentTime)
    whiteNoise.stop(audioContext.currentTime + 1.5)
  }

  // Getters
  isMusicEnabled() {
    return this.musicEnabled
  }

  isSoundEffectsEnabled() {
    return this.soundEffectsEnabled
  }
}

// Lazy singleton - only create when accessed in browser
let soundSystemInstance: SoundSystem | null = null

function getSoundSystem(): SoundSystem {
  if (typeof window === 'undefined') {
    // Return a dummy instance on server
    return {
      toggleMusic: () => {},
      playWarpSound: () => {},
      playClickSound: () => {},
      playSuccessSound: () => {},
      playErrorSound: () => {},
      isMusicEnabled: () => false,
      isSoundEffectsEnabled: () => false,
    } as any
  }
  
  if (!soundSystemInstance) {
    soundSystemInstance = new SoundSystem()
  }
  return soundSystemInstance
}

// Export individual functions for easy use
export const playWarpSound = () => getSoundSystem().playWarpSound()
export const playClickSound = () => getSoundSystem().playClickSound()
export const playSuccessSound = () => getSoundSystem().playSuccessSound()
export const playErrorSound = () => getSoundSystem().playErrorSound()
export const playScanSound = () => getSoundSystem().playScanSound()
export const playMapSound = () => getSoundSystem().playMapSound()
export const playHyperspaceSound = () => getSoundSystem().playHyperspaceSound()
export const toggleMusic = () => getSoundSystem().toggleMusic()
export const isMusicEnabled = () => getSoundSystem().isMusicEnabled()
export const initMusic = () => getSoundSystem().initMusic()
