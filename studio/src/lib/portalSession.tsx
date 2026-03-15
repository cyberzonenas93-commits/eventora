/* eslint-disable react-refresh/only-export-components */
import {
  createUserWithEmailAndPassword,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signOut as firebaseSignOut,
  updateProfile,
  type User,
} from 'firebase/auth'
import { doc, onSnapshot, setDoc, serverTimestamp } from 'firebase/firestore'
import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'

import { auth, db } from '../firebase'
import { createEmptyApplication } from './portalData'
import type {
  OrganizerApplication,
  OrganizerApplicationStatus,
  UserProfile,
} from './types'

interface PortalSessionValue {
  user: User | null
  profile: UserProfile | null
  application: OrganizerApplication | null
  loading: boolean
  status: OrganizerApplicationStatus | 'guest'
  organizationId: string | null
  signIn: (email: string, password: string) => Promise<void>
  signUp: (input: {
    displayName: string
    email: string
    password: string
    phone?: string
  }) => Promise<void>
  signOut: () => Promise<void>
}

const PortalSessionContext = createContext<PortalSessionValue | null>(null)

export function PortalSessionProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [profile, setProfile] = useState<UserProfile | null>(null)
  const [application, setApplication] = useState<OrganizerApplication | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let stopProfile = () => {}
    let stopApplication = () => {}

    const stopAuth = onAuthStateChanged(auth, (nextUser) => {
      stopProfile()
      stopApplication()
      setUser(nextUser)
      setProfile(null)
      setApplication(null)

      if (!nextUser) {
        setLoading(false)
        return
      }

      let profileReady = false
      let applicationReady = false

      const finishLoading = () => {
        if (profileReady && applicationReady) {
          setLoading(false)
        }
      }

      setLoading(true)
      stopProfile = onSnapshot(doc(db, 'users', nextUser.uid), (snapshot) => {
        const data = snapshot.data()
        setProfile(
          data
            ? {
                displayName: String(data.displayName ?? nextUser.displayName ?? ''),
                email: String(data.email ?? nextUser.email ?? ''),
                phone: String(data.phone ?? ''),
                roles: Array.isArray(data.roles) ? data.roles.map(String) : ['attendee'],
                defaultOrganizationId: String(data.defaultOrganizationId ?? ''),
                organizerApplicationStatus:
                  (data.organizerApplicationStatus as OrganizerApplicationStatus | undefined) ??
                  'not_started',
              }
            : null,
        )
        profileReady = true
        finishLoading()
      })

      stopApplication = onSnapshot(
        doc(db, 'organizer_applications', nextUser.uid),
        (snapshot) => {
          const data = snapshot.data()
          setApplication(
            data
              ? createEmptyApplication({
                  ...data,
                  userId: nextUser.uid,
                  status: (data.status as OrganizerApplicationStatus | undefined) ?? 'draft',
                })
              : null,
          )
          applicationReady = true
          finishLoading()
        },
      )
    })

    return () => {
      stopProfile()
      stopApplication()
      stopAuth()
    }
  }, [])

  const value = useMemo<PortalSessionValue>(() => {
    const applicationStatus =
      application?.status ?? profile?.organizerApplicationStatus ?? 'not_started'
    const status = user ? applicationStatus : 'guest'
    const organizationId =
      application?.organizationId || profile?.defaultOrganizationId || null

    return {
      user,
      profile,
      application,
      loading,
      status,
      organizationId,
      async signIn(email, password) {
        await signInWithEmailAndPassword(auth, email.trim(), password)
      },
      async signUp(input) {
        const credential = await createUserWithEmailAndPassword(
          auth,
          input.email.trim(),
          input.password,
        )
        await updateProfile(credential.user, {
          displayName: input.displayName.trim(),
        })
        await setDoc(
          doc(db, 'users', credential.user.uid),
          {
            displayName: input.displayName.trim(),
            email: input.email.trim(),
            phone: input.phone?.trim() || null,
            roles: ['attendee'],
            organizerApplicationStatus: 'not_started',
            notificationPrefs: {
              pushEnabled: true,
              smsEnabled: true,
              marketingOptIn: false,
            },
            createdAt: serverTimestamp(),
            updatedAt: serverTimestamp(),
          },
          { merge: true },
        )
      },
      async signOut() {
        await firebaseSignOut(auth)
      },
    }
  }, [application, loading, profile, user])

  return (
    <PortalSessionContext.Provider value={value}>
      {children}
    </PortalSessionContext.Provider>
  )
}

export function usePortalSession() {
  const context = useContext(PortalSessionContext)
  if (!context) {
    throw new Error('usePortalSession must be used within PortalSessionProvider')
  }
  return context
}
