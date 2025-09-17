interface ShipArtProps {
  className?: string
}

export default function ShipArt({ className = '' }: ShipArtProps) {
  return (
    <svg
      viewBox="0 0 200 120"
      className={className}
      style={{ maxWidth: '300px', height: 'auto' }}
    >
      {/* Ship hull - main body */}
      <path
        d="M 50 60 L 150 60 L 145 75 L 55 75 Z"
        fill="none"
        stroke="var(--accent)"
        strokeWidth="2"
        strokeLinejoin="round"
      />
      
      {/* Ship nose */}
      <path
        d="M 50 60 L 30 50 L 30 70 L 50 75"
        fill="none"
        stroke="var(--accent)"
        strokeWidth="2"
        strokeLinejoin="round"
      />
      
      {/* Engine nacelles */}
      <path
        d="M 140 45 L 160 40 L 165 50 L 145 55"
        fill="none"
        stroke="var(--accent)"
        strokeWidth="2"
        strokeLinejoin="round"
      />
      <path
        d="M 140 75 L 160 80 L 165 70 L 145 65"
        fill="none"
        stroke="var(--accent)"
        strokeWidth="2"
        strokeLinejoin="round"
      />
      
      {/* Engine glow */}
      <ellipse
        cx="155"
        cy="45"
        rx="8"
        ry="3"
        fill="var(--accent)"
        opacity="0.6"
      />
      <ellipse
        cx="155"
        cy="75"
        rx="8"
        ry="3"
        fill="var(--accent)"
        opacity="0.6"
      />
      
      {/* Bridge/cockpit */}
      <circle
        cx="80"
        cy="50"
        r="8"
        fill="none"
        stroke="var(--accent)"
        strokeWidth="1.5"
      />
      
      {/* Sensor array */}
      <path
        d="M 25 50 L 20 45 L 20 55 L 25 50"
        fill="none"
        stroke="var(--accent)"
        strokeWidth="1.5"
      />
      
      {/* Wing details */}
      <path
        d="M 100 45 L 120 40 L 120 50 L 100 55"
        fill="none"
        stroke="var(--accent)"
        strokeWidth="1"
        opacity="0.7"
      />
      <path
        d="M 100 75 L 120 80 L 120 70 L 100 65"
        fill="none"
        stroke="var(--accent)"
        strokeWidth="1"
        opacity="0.7"
      />
      
      {/* Hull plating lines */}
      <path
        d="M 60 60 L 60 75"
        stroke="var(--accent)"
        strokeWidth="1"
        opacity="0.5"
      />
      <path
        d="M 80 60 L 80 75"
        stroke="var(--accent)"
        strokeWidth="1"
        opacity="0.5"
      />
      <path
        d="M 100 60 L 100 75"
        stroke="var(--accent)"
        strokeWidth="1"
        opacity="0.5"
      />
      <path
        d="M 120 60 L 120 75"
        stroke="var(--accent)"
        strokeWidth="1"
        opacity="0.5"
      />
      
      {/* Subtle glow effect */}
      <defs>
        <filter id="glow">
          <feGaussianBlur stdDeviation="3" result="coloredBlur"/>
          <feMerge> 
            <feMergeNode in="coloredBlur"/>
            <feMergeNode in="SourceGraphic"/>
          </feMerge>
        </filter>
      </defs>
      
      {/* Apply glow to main ship outline */}
      <path
        d="M 50 60 L 150 60 L 145 75 L 55 75 Z"
        fill="none"
        stroke="var(--accent)"
        strokeWidth="1"
        strokeLinejoin="round"
        filter="url(#glow)"
        opacity="0.3"
      />
    </svg>
  )
}
