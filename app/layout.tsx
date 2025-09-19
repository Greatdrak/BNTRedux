import './globals.css'
import { Inter } from 'next/font/google'
import { SWRConfig } from 'swr'

const inter = Inter({ subsets: ['latin'] })

export const metadata = {
  title: 'BNT Redux',
  description: 'A space trading game',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <SWRConfig value={{ revalidateOnFocus: false, revalidateOnReconnect: false, dedupingInterval: 15000, focusThrottleInterval: 30000 }}>
          {children}
        </SWRConfig>
      </body>
    </html>
  )
}
