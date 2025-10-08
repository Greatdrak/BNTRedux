import React from 'react'

type Props = {
  label: string
  value: number
  max?: number
  size?: number
  color?: string
  thick?: number
  title?: string
}

export default function StatRing({ label, value, max = 100, size = 84, color = '#63e6be', thick = 8, title }: Props) {
  const radius = (size - thick) / 2
  const circ = 2 * Math.PI * radius
  const pct = Math.max(0, Math.min(1, max ? value / max : 1))
  const dash = circ * pct

  return (
    <div style={{ width: size, height: size, position: 'relative' }} title={title || label}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
        <circle cx={size/2} cy={size/2} r={radius} stroke="rgba(255,255,255,0.08)" strokeWidth={thick} fill="none" />
        <circle
          cx={size/2}
          cy={size/2}
          r={radius}
          stroke={color}
          strokeWidth={thick}
          fill="none"
          strokeLinecap="round"
          strokeDasharray={`${dash} ${circ - dash}`}
          transform={`rotate(-90 ${size/2} ${size/2})`}
          style={{ filter: `drop-shadow(0 0 6px ${color}55)` }}
        />
      </svg>
      <div style={{ position:'absolute', inset:0, display:'flex', alignItems:'center', justifyContent:'center', flexDirection:'column', pointerEvents:'none' }}>
        <div style={{ fontSize:12, color:'#aee8ff' }}>{label}</div>
        <div style={{ fontWeight:700, color:'#e7faff', fontSize:14 }}>{max ? Math.floor(pct*100) : value}%</div>
      </div>
    </div>
  )
}
