'use client'

import { useState, useEffect } from 'react'
import Image from 'next/image'
import styles from './TutorialOverlay.module.css'

interface TutorialOverlayProps {
  open: boolean
  onClose: () => void
  onComplete: () => void
  onHighlightPort: (highlight: boolean) => void
  currentStep: number
  onStepChange: (step: number) => void
  onStepData?: (stepData: TutorialStep | null) => void
}

type TutorialCharacter = 'man' | 'woman' | 'any'
type TutorialStep = {
  id: number
  character: TutorialCharacter
  message: string
  options?: Array<{
    text: string
    action: () => void
  }>
  voiceover?: string // mp3 placeholder
  highlightPort?: boolean
  highlightFullScan?: boolean
  highlightPortSector?: boolean
  highlightMaxBuy?: boolean
}

const tutorialSteps: TutorialStep[] = [
  {
    id: 1,
    character: 'man',
    message: "Hello and welcome to space, cadet. You're looking kind of poor and your ship's in piss poor condition. Enter the special port and upgrade your hull so you can carry some goods and start trading.",
    voiceover: 'tutorial_man_welcome.mp3',
    highlightPort: true,
    options: [
      {
        text: "I'd rather learn from an astro-lady",
        action: () => {} // Will be handled by step change
      }
    ]
  },
  {
    id: 2,
    character: 'woman',
    message: "Men only think about their ships and how big they can build them. I can teach you how to really use it darlin'. Go ahead and enter the Special port.",
    voiceover: 'tutorial_woman_welcome.mp3',
    highlightPort: true
  },
  {
    id: 3,
    character: 'any',
    message: "Perfect! Now you're in the special port. This is where you can upgrade your ship's capabilities. Try upgrading your hull first - it will increase your cargo capacity.",
    voiceover: 'tutorial_special_port.mp3',
    highlightPort: false
  },
  {
    id: 4,
    character: 'any',
    message: "Let's go earn some credits. Check out the sectors connected to Sector 0 by clicking Full Scan.",
    voiceover: 'tutorial_full_scan.mp3',
    highlightFullScan: true
  },
  {
    id: 5,
    character: 'any',
    message: "Look at the different port types and their icons. Trading between Goods and Ore is usually the best profit. You can make a profit off trading organics, but they're best used to feed the colonists on planets you will capture in the future. Energy isn't stored in your cargo, it's stored in your Power Batteries and it's used for combat between ships and planets. Click on a sector with a Goods or an Ore port.",
    voiceover: 'tutorial_port_types.mp3',
    highlightPortSector: true
  },
  {
    id: 6,
    character: 'any',
    message: "Okay now enter the port and buy a commodity.",
    voiceover: 'tutorial_enter_port.mp3',
    highlightPort: true
  },
  {
    id: 7,
    character: 'any',
    message: "Ports will only sell their native resource, but they will buy everything else. Click on Max Buy to buy as much of a commodity that your cargo can handle and then hit the Buy button.",
    voiceover: 'tutorial_buy_commodity.mp3',
    highlightMaxBuy: true
  },
  {
    id: 8,
    character: 'any',
    message: "Great job! Now go find a different port to sell your commodity and make some credits.",
    voiceover: 'tutorial_sell_commodity.mp3',
    highlightPort: false
  }
]

export default function TutorialOverlay({
  open,
  onClose,
  onComplete,
  onHighlightPort,
  currentStep,
  onStepChange,
  onStepData
}: TutorialOverlayProps) {
  const [currentCharacter, setCurrentCharacter] = useState<TutorialCharacter>('man')
  const [isVisible, setIsVisible] = useState(false)

  const currentStepData = tutorialSteps.find(step => step.id === currentStep)

  useEffect(() => {
    if (open) {
      // Trigger slide-in animation
      setTimeout(() => setIsVisible(true), 100)
    } else {
      setIsVisible(false)
    }
  }, [open])

  useEffect(() => {
    if (currentStepData) {
      // Only change character if it's not 'any' - keep the current character
      if (currentStepData.character !== 'any') {
        setCurrentCharacter(currentStepData.character)
      }
      
      // Handle port highlighting
      if (currentStepData.highlightPort !== undefined) {
        onHighlightPort(currentStepData.highlightPort)
      }
      
      // Pass step data to parent for other highlighting
      onStepData?.(currentStepData)
    } else {
      onStepData?.(null)
    }
  }, [currentStepData, onHighlightPort, onStepData])

  const handleOptionClick = (option: { text: string; action: () => void }) => {
    if (option.text.includes("astro-lady")) {
      // Switch to woman character and go to step 2
      setCurrentCharacter('woman')
      onStepChange(2)
    } else {
      option.action()
    }
  }

  const handleCancel = () => {
    onComplete()
  }

  if (!open || !currentStepData) {
    return null
  }

  // Move to right side when in special port (step 3) or when scanning warps (step 5)
  const isRightSide = currentStep === 3 || currentStep === 5

  return (
    <div className={`${styles.tutorialOverlay} ${isVisible ? styles.visible : ''} ${isRightSide ? styles.rightSide : ''}`}>
      {/* Character */}
      <Image
        src={`/images/Tutorial${currentCharacter === 'man' ? 'Man' : 'Woman'}.png`}
        alt={currentCharacter === 'man' ? 'Tutorial Man' : 'Tutorial Woman'}
        width={300}
        height={450}
        className={styles.characterImg}
      />

      {/* Text */}
      <div className={styles.speechText}>
        {currentStepData.message}
      </div>

      {/* Options */}
      {currentStepData.options && currentStepData.options.length > 0 && (
        <div className={styles.optionsContainer}>
          {currentStepData.options.map((option, index) => (
            <button
              key={index}
              className={styles.optionButton}
              onClick={() => handleOptionClick(option)}
            >
              {option.text}
            </button>
          ))}
          {/* Next Tip Button */}
          <button 
            className={styles.nextTipButton}
            onClick={() => {
              if (currentStep < tutorialSteps.length) {
                onStepChange(currentStep + 1)
              } else {
                onComplete()
              }
            }}
            title="Skip this step"
          >
            {currentStep < tutorialSteps.length ? 'Next Tip' : 'Finish Tutorial'}
          </button>
          {/* Cancel Button */}
          <button 
            className={styles.cancelButton}
            onClick={handleCancel}
            title="Cancel Tutorial"
          >
            Cancel
          </button>
        </div>
      )}

      {/* Buttons for steps without options */}
      {(!currentStepData.options || currentStepData.options.length === 0) && (
        <div className={styles.optionsContainer}>
          {/* Next Tip Button */}
          <button 
            className={styles.nextTipButton}
            onClick={() => {
              if (currentStep < tutorialSteps.length) {
                onStepChange(currentStep + 1)
              } else {
                onComplete()
              }
            }}
            title="Skip this step"
          >
            {currentStep < tutorialSteps.length ? 'Next Tip' : 'Finish Tutorial'}
          </button>
          {/* Cancel Button */}
          <button 
            className={styles.cancelButton}
            onClick={handleCancel}
            title="Cancel Tutorial"
          >
            Cancel
          </button>
        </div>
      )}
    </div>
  )
}
