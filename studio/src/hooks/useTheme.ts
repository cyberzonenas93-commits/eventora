import { useCallback, useEffect, useState } from 'react'

type Theme = 'light' | 'dark'
const OVERRIDE_KEY = 'vennuzo-theme-override'

function getAutoTheme(): Theme {
  const hour = new Date().getHours()
  return hour >= 6 && hour < 18 ? 'light' : 'dark'
}

export function useTheme() {
  const [override, setOverride] = useState<Theme | null>(() => {
    try {
      const stored = localStorage.getItem(OVERRIDE_KEY)
      return stored === 'light' || stored === 'dark' ? stored : null
    } catch {
      return null
    }
  })
  const [autoTheme, setAutoTheme] = useState<Theme>(getAutoTheme)

  useEffect(() => {
    const interval = setInterval(() => {
      setAutoTheme(getAutoTheme())
    }, 60_000)
    return () => clearInterval(interval)
  }, [])

  const theme = override ?? autoTheme
  const isAuto = override === null

  // 3-state cycle: auto → force-dark → force-light → auto
  const toggleOverride = useCallback(() => {
    try {
      if (override === null) {
        localStorage.setItem(OVERRIDE_KEY, 'dark')
        setOverride('dark')
      } else if (override === 'dark') {
        localStorage.setItem(OVERRIDE_KEY, 'light')
        setOverride('light')
      } else {
        localStorage.removeItem(OVERRIDE_KEY)
        setOverride(null)
      }
    } catch {
      // localStorage unavailable
    }
  }, [override])

  return { theme, isAuto, toggleOverride }
}
