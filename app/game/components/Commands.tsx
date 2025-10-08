'use client'

import { useEffect, useState } from 'react'

export default function Commands() {
  const [openLogs, setOpenLogs] = useState(false)
  const [logs, setLogs] = useState<any[]>([])

  useEffect(()=>{
    if (!openLogs) return
    fetch('/api/logs').then(r=>r.json()).then(d=>{
      if (d?.logs) setLogs(d.logs)
    })
  }, [openLogs])

  return (
    <div style={{ display:'flex', gap:8 }}>
      <button onClick={()=> setOpenLogs(true)}>📝 Activity</button>
      {openLogs && (
        <div style={{ position:'fixed', inset:0, background:'rgba(0,0,0,.6)', display:'flex', alignItems:'center', justifyContent:'center', zIndex:1000 }} onClick={()=> setOpenLogs(false)}>
          <div style={{ background:'var(--panel)', border:'1px solid var(--line)', borderRadius:8, width:480, maxHeight:'70vh', overflow:'auto', padding:16 }} onClick={e=> e.stopPropagation()}>
            <div style={{ display:'flex', justifyContent:'space-between', marginBottom:12 }}>
              <h3 style={{ margin:0 }}>Activity</h3>
              <button onClick={()=> setOpenLogs(false)}>✕</button>
            </div>
            <ul style={{ listStyle:'none', margin:0, padding:0 }}>
              {logs.map(l => (
                <li key={l.id} style={{ borderBottom:'1px solid var(--line)', padding:'8px 0' }}>
                  <div style={{ fontSize:12, opacity:.7 }}>{new Date(l.occurred_at).toLocaleString()}</div>
                  <div style={{ fontWeight:600 }}>{l.message}</div>
                </li>
              ))}
              {!logs.length && <li style={{ opacity:.7 }}>No activity yet.</li>}
            </ul>
          </div>
        </div>
      )}
    </div>
  )
}


