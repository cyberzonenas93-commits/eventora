import { createContext, type ReactNode, useContext } from 'react'

import { useTheme } from '../hooks/useTheme'

interface ThemeContextValue {
  theme: 'light' | 'dark'
  isAuto: boolean
  toggleOverride: () => void
}

const ThemeContext = createContext<ThemeContextValue>({
  theme: 'dark',
  isAuto: true,
  toggleOverride: () => {},
})

export function ThemeProvider({ children }: { children: ReactNode }) {
  const themeValue = useTheme()
  return <ThemeContext.Provider value={themeValue}>{children}</ThemeContext.Provider>
}

export function useThemeContext() {
  return useContext(ThemeContext)
}
