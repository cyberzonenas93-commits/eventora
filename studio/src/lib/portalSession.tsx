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

import { auth } from '../firebaseAuth'
import { db } from '../firebaseDb'
import { createEmptyApplication } from './organizerApplication'
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
  adminRole: string
  isAdmin: boolean
  isSuperAdmin: boolean
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
  const [adminRole, setAdminRole] = useState('')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let stopProfile = () => {}
    let stopApplication = () => {}
    let stopAdmin = () => {}

    const stopAuth = onAuthStateChanged(auth, (nextUser) => {
      stopProfile()
      stopApplication()
      stopAdmin()
      setUser(nextUser)
      setProfile(null)
      setApplication(null)
      setAdminRole('')

      if (!nextUser) {
        setLoading(false)
        return
      }

      let profileReady = false
      let applicationReady = false
      let adminReady = false

      const finishLoading = () => {
        if (profileReady && applicationReady && adminReady) {
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
                roles: Array.isArray(data.roles) ? data.roles.map(String) : ['organizer'],
                adminRole: adminRole.trim(),
                defaultOrganizationId: String(
                  data.defaultOrganizationId ?? `org_${nextUser.uid}`,
                ),
                organizerApplicationStatus:
                  (data.organizerApplicationStatus as OrganizerApplicationStatus | undefined) ??
                  'active',
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

      stopAdmin = onSnapshot(doc(db, 'admins', nextUser.uid), (snapshot) => {
        const data = snapshot.data()
        setAdminRole(String(data?.role ?? ''))
        adminReady = true
        finishLoading()
      })
    })

    return () => {
      stopProfile()
      stopApplication()
      stopAdmin()
      stopAuth()
    }
  }, [])

  const value = useMemo<PortalSessionValue>(() => {
    const normalizedAdminRole = adminRole.trim().toLowerCase()
    const isSuperAdmin = normalizedAdminRole === 'superadmin'
    const isAdmin = normalizedAdminRole === 'admin' || isSuperAdmin
    const applicationStatus =
      application?.status ?? profile?.organizerApplicationStatus ?? 'active'
    const status = user ? (isAdmin ? applicationStatus : 'active') : 'guest'
    const organizationId =
      application?.organizationId || profile?.defaultOrganizationId || (user ? `org_${user.uid}` : null)
    const profileWithAdminRole = profile
      ? {
          ...profile,
          adminRole: adminRole.trim(),
        }
      : null

    return {
      user,
      profile: profileWithAdminRole,
      application,
      loading,
      status,
      organizationId,
      adminRole: adminRole.trim(),
      isAdmin,
      isSuperAdmin,
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
            roles: ['organizer'],
            defaultOrganizationId: `org_${credential.user.uid}`,
            organizerApplicationStatus: 'active',
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
        await setDoc(
          doc(db, 'organizations', `org_${credential.user.uid}`),
          {
            id: `org_${credential.user.uid}`,
            ownerId: credential.user.uid,
            name: input.displayName.trim(),
            status: 'active',
            createdAt: serverTimestamp(),
            updatedAt: serverTimestamp(),
          },
          { merge: true },
        )
        await setDoc(
          doc(db, 'organizer_applications', credential.user.uid),
          createEmptyApplication({
            userId: credential.user.uid,
            organizerName: input.displayName.trim(),
            contactPerson: input.displayName.trim(),
            email: input.email.trim(),
            phone: input.phone?.trim() || '',
            organizationId: `org_${credential.user.uid}`,
            status: 'active',
          }),
          { merge: true },
        )
      },
      async signOut() {
        await firebaseSignOut(auth)
      },
    }
  }, [adminRole, application, loading, profile, user])

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
