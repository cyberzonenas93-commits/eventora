import { Component, type ErrorInfo, type ReactNode } from 'react'
import { Link } from 'react-router-dom'

import { copy } from '../lib/copy'

type Props = {
  children: ReactNode
  fallback?: ReactNode
}

type State = {
  hasError: boolean
  error: Error | null
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    if (typeof console !== 'undefined' && console.error) {
      console.error('ErrorBoundary caught an error', error, errorInfo)
    }
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: null })
  }

  render() {
    if (this.state.hasError && this.state.error) {
      if (this.props.fallback) {
        return this.props.fallback
      }
      return (
        <div className="status-page status-page--reference">
          <div className="status-card">
            <div className="status-card__header">
              <h1>{copy.errorBoundaryTitle}</h1>
              <p>{copy.errorBoundaryMessage}</p>
            </div>
            <div className="status-actions" style={{ marginTop: '1.5rem', gap: '0.75rem' }}>
              <button
                type="button"
                className="button button--primary"
                onClick={this.handleRetry}
              >
                {copy.errorBoundaryAction}
              </button>
              <Link to="/" className="button button--secondary">
                {copy.errorBoundaryHome}
              </Link>
            </div>
          </div>
        </div>
      )
    }
    return this.props.children
  }
}
