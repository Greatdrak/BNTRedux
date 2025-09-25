interface ShipArtProps {
  level?: number
  size?: number
  className?: string
}

export default function ShipArt({ level = 1, size = 100, className = '' }: ShipArtProps) {
  return (
    <img
      src="/images/ShipLevel1.png"
      alt={`Ship Level ${level}`}
      className={className}
      style={{ 
        width: `${size}px`, 
        height: 'auto',
        maxWidth: '100%'
      }}
    />
  )
}
