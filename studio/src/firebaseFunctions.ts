import { getFunctions } from 'firebase/functions'

import { app } from './firebaseApp'

export const functions = getFunctions(app, 'us-central1')
