import { initializeApp } from 'firebase/app'
import { getAuth } from 'firebase/auth'
import { getFirestore } from 'firebase/firestore'
import { getFunctions } from 'firebase/functions'
import { getStorage } from 'firebase/storage'

const firebaseConfig = {
  apiKey: 'AIzaSyAKv05vJYQgLPb0vDdEUt2aPZmv5rID42U',
  authDomain: 'eventora-10063.firebaseapp.com',
  projectId: 'eventora-10063',
  storageBucket: 'eventora-10063.firebasestorage.app',
  messagingSenderId: '872808273884',
  appId: '1:872808273884:web:d73aeb08ba0941b28c2119',
}

const app = initializeApp(firebaseConfig)

export const auth = getAuth(app)
export const db = getFirestore(app)
export const storage = getStorage(app)
export const functions = getFunctions(app, 'us-central1')
