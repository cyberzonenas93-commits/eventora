import { type FormEvent, useEffect, useMemo, useState } from 'react'
import {
  ArrowRight,
  BadgeCheck,
  CalendarDays,
  CalendarRange,
  ChevronLeft,
  ChevronRight,
  Filter,
  LayoutGrid,
  ListChecks,
  MapPin,
  Search,
  SlidersHorizontal,
  Ticket,
  UsersRound,
} from 'lucide-react'
import { Link, useSearchParams } from 'react-router-dom'

import { copy } from '../lib/copy'
import { formatDateTime } from '../lib/formatters'
import {
  getDateParts,
  getDemandLabel,
  getPriceLabel,
  getTicketAvailability,
} from '../lib/eventCardHelpers'
import { EVENT_CATEGORIES, canonicalCategoryId, categoryById, normalizeCategoryToken } from '../lib/eventTaxonomy'
import { listPublicEvents } from '../lib/portalData'
import { trackEvent } from '../lib/analytics'
import type { PortalEvent } from '../lib/types'

const CATEGORY_FILTERS = ['All', ...EVENT_CATEGORIES.map((category) => category.id)]
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
type PublicEventsView = 'grid' | 'calendar'

function getCtaLabel(event: PortalEvent): string {
  return event.ticketingEnabled && event.tiers.length > 0 ? 'Get tickets' : 'RSVP'
}

function toEventDate(event: PortalEvent): Date {
  return new Date(event.startAt)
}

function toDateKey(date: Date): string {
  return [
    date.getFullYear(),
    String(date.getMonth() + 1).padStart(2, '0'),
    String(date.getDate()).padStart(2, '0'),
  ].join('-')
}

function startOfMonth(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), 1)
}

function addMonths(date: Date, amount: number): Date {
  return new Date(date.getFullYear(), date.getMonth() + amount, 1)
}

function getCalendarDays(month: Date): Date[] {
  const first = startOfMonth(month)
  const cursor = new Date(first)
  cursor.setDate(first.getDate() - first.getDay())
  return Array.from({ length: 42 }, (_, index) => {
    const day = new Date(cursor)
    day.setDate(cursor.getDate() + index)
    return day
  })
}

function getMonthLabel(date: Date): string {
  return new Intl.DateTimeFormat('en', { month: 'long', year: 'numeric' }).format(date)
}

function getDayLabel(date: Date): string {
  return new Intl.DateTimeFormat('en', { weekday: 'long', month: 'short', day: 'numeric' }).format(date)
}

export function PublicEventsPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [loading, setLoading] = useState(true)
  const [query, setQuery] = useState(searchParams.get('q') ?? '')
  const [category, setCategory] = useState(() => {
    const raw = searchParams.get('category')
    return raw ? canonicalCategoryId(raw) : 'All'
  })
  const [view, setView] = useState<PublicEventsView>('grid')
  const [calendarMonth, setCalendarMonth] = useState(() => startOfMonth(new Date()))

  useEffect(() => {
    let cancelled = false
    listPublicEvents(100)
      .then((list) => {
        if (!cancelled) setEvents(list)
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => { cancelled = true }
  }, [])

  useEffect(() => {
    if (!searchParams.has('view')) return
    const params = new URLSearchParams(searchParams)
    params.delete('view')
    setSearchParams(params, { replace: true })
  }, [searchParams, setSearchParams])

  const stats = useMemo(() => {
    const cities = new Set(events.map((event) => event.city).filter(Boolean)).size
    const ticketed = events.filter((event) => event.ticketingEnabled).length
    const audience = events.reduce((sum, event) => sum + event.rsvpCount + event.likesCount, 0)
    return [
      { label: 'Events to explore', value: events.length, Icon: CalendarDays },
      { label: 'Ticketed plans', value: ticketed, Icon: Ticket },
      { label: 'Cities', value: cities || 1, Icon: MapPin },
      { label: 'People interested', value: audience, Icon: UsersRound },
    ]
  }, [events])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    const selectedCategory = category === 'All' ? 'All' : canonicalCategoryId(category)
    return events.filter((event) => {
      const searchText = [
        event.title,
        event.venue,
        event.city,
        event.description,
        event.mood,
        categoryById(event.categoryId).label,
        categoryById(event.categoryId).shortLabel,
        ...event.tags,
      ].join(' ').toLowerCase()

      const matchesQuery = !q || searchText.includes(q)
      const matchesCategory =
        category === 'All' ||
        event.categoryId === selectedCategory ||
        event.tags.some((tag) => normalizeCategoryToken(tag) === selectedCategory) ||
        searchText.includes(selectedCategory.replace(/_/g, ' '))
      return matchesQuery && matchesCategory
    })
  }, [events, query, category])

  const calendarEventsByDay = useMemo(() => {
    const groups = new Map<string, PortalEvent[]>()
    filtered.forEach((event) => {
      const key = toDateKey(toEventDate(event))
      const group = groups.get(key) ?? []
      group.push(event)
      groups.set(key, group)
    })
    groups.forEach((group) => {
      group.sort((a, b) => toEventDate(a).getTime() - toEventDate(b).getTime())
    })
    return groups
  }, [filtered])

  const monthDays = useMemo(() => getCalendarDays(calendarMonth), [calendarMonth])
  const monthEvents = useMemo(() => (
    filtered
      .filter((event) => {
        const date = toEventDate(event)
        return date.getFullYear() === calendarMonth.getFullYear() && date.getMonth() === calendarMonth.getMonth()
      })
      .sort((a, b) => toEventDate(a).getTime() - toEventDate(b).getTime())
  ), [filtered, calendarMonth])

  function updateUrl(nextQuery: string, nextCategory: string) {
    const params = new URLSearchParams()
    const cleanQuery = nextQuery.trim()
    if (cleanQuery) params.set('q', cleanQuery)
    if (nextCategory !== 'All') params.set('category', nextCategory)
    setSearchParams(params)
  }

  function handleView(nextView: PublicEventsView) {
    setView(nextView)
    void trackEvent('public_search', {
      interaction: 'view_changed',
      view: nextView,
      result_count: filtered.length,
    }, {
      area: 'public_events',
    })
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    updateUrl(query, category)
    void trackEvent('public_search', {
      category_selected: category !== 'All',
      query_entered: Boolean(query.trim()),
      result_count: filtered.length,
    }, {
      area: 'public_events',
    })
  }

  function handleCategory(nextCategory: string) {
    setCategory(nextCategory)
    updateUrl(query, nextCategory)
    void trackEvent('public_search', {
      category_selected: nextCategory !== 'All',
      query_entered: Boolean(query.trim()),
    }, {
      area: 'public_events',
    })
  }

  return (
    <div className="public-page public-events-page">
      <section className="page-hero page-hero--events page-hero--explore public-events-hero">
        <div className="page-hero__content">
          <span className="home-hero__badge">
            <BadgeCheck size={15} />
            Curated public events
          </span>
          <h1>Find your next great plan.</h1>
          <p>
            Browse events by city, venue, category, or name, then book tickets or RSVP
            without the back-and-forth.
          </p>
          <form className="home-hero__search public-events-search" onSubmit={handleSubmit}>
            <Search size={18} aria-hidden="true" />
            <input
              type="search"
              placeholder="Search events, venues, or cities"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              aria-label="Search events"
            />
            <button type="submit">Search</button>
          </form>
        </div>
        <div className="public-events-hero__panel">
          <div className="public-events-hero__panel-header">
            <SlidersHorizontal size={18} />
            <span>What is live now</span>
          </div>
          <div className="public-events-hero__stats">
            {stats.map(({ label, value, Icon }) => (
              <div key={label}>
                <Icon size={17} />
                <strong>{loading ? '...' : value}</strong>
                <span>{label}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="public-events-filters" aria-label="Event filters">
        <div className="public-events-filters__label">
          <Filter size={16} />
          Categories
        </div>
        <div className="public-events-filters__row">
            {CATEGORY_FILTERS.map((filter) => (
              <button
                key={filter}
                type="button"
                className={`public-events-filters__chip ${filter === category ? 'public-events-filters__chip--active' : ''}`}
                onClick={() => handleCategory(filter)}
              >
                {filter === 'All' ? 'All' : categoryById(filter).shortLabel}
              </button>
            ))}
        </div>
      </section>

      <div className="public-events-resultbar">
        <div>
          <span>{loading ? 'Loading' : filtered.length}</span>
          <strong>{filtered.length === 1 ? 'event ready for you' : 'events ready for you'}</strong>
        </div>
        <div className="public-events-resultbar__actions">
          <div className="events-dashboard__view-toggle public-events-view-toggle" role="group" aria-label="Event view">
            <button
              type="button"
              className={view === 'grid' ? 'is-active' : ''}
              onClick={() => handleView('grid')}
            >
              <LayoutGrid size={14} />
              Cards
            </button>
            <button
              type="button"
              className={view === 'calendar' ? 'is-active' : ''}
              onClick={() => handleView('calendar')}
            >
              <CalendarRange size={14} />
              Calendar
            </button>
          </div>
          {(query.trim() || category !== 'All') && (
            <button type="button" onClick={() => { setQuery(''); setCategory('All'); setSearchParams(new URLSearchParams()) }}>
              Reset search
            </button>
          )}
        </div>
      </div>

      {loading ? (
        <p className="page-loader">{copy.loading}</p>
      ) : filtered.length === 0 ? (
        <div className="empty-card public-events-empty">
          <h4>{query.trim() || category !== 'All' ? 'No perfect match yet' : 'No events are live yet'}</h4>
          <p>
            {query.trim() || category !== 'All'
              ? 'Try a broader search, switch categories, or reset your filters.'
              : 'Check back soon, or be the first organizer to bring an event to Vennuzo.'}
          </p>
          <Link to="/studio" className="button button--secondary">
            Launch your event
            <ArrowRight size={15} />
          </Link>
        </div>
      ) : view === 'calendar' ? (
        <section className="public-events-calendar" aria-label="Events calendar">
          <div className="public-events-calendar__header">
            <div>
              <p className="eyebrow">Calendar</p>
              <h2>{getMonthLabel(calendarMonth)}</h2>
              <span>{monthEvents.length} {monthEvents.length === 1 ? 'event' : 'events'} this month</span>
            </div>
            <div className="public-events-calendar__nav">
              <button type="button" aria-label="Previous month" onClick={() => setCalendarMonth((current) => addMonths(current, -1))}>
                <ChevronLeft size={16} />
              </button>
              <button type="button" onClick={() => setCalendarMonth(startOfMonth(new Date()))}>Today</button>
              <button type="button" aria-label="Next month" onClick={() => setCalendarMonth((current) => addMonths(current, 1))}>
                <ChevronRight size={16} />
              </button>
            </div>
          </div>
          <div className="public-events-calendar__weekdays" aria-hidden="true">
            {WEEKDAYS.map((day) => <span key={day}>{day}</span>)}
          </div>
          <div className="public-events-calendar__grid">
            {monthDays.map((day) => {
              const key = toDateKey(day)
              const dayEvents = calendarEventsByDay.get(key) ?? []
              const inMonth = day.getMonth() === calendarMonth.getMonth()
              const isToday = key === toDateKey(new Date())
              return (
                <div
                  key={key}
                  className={`public-events-calendar__day${inMonth ? '' : ' public-events-calendar__day--muted'}${isToday ? ' public-events-calendar__day--today' : ''}`}
                >
                  <div className="public-events-calendar__date">
                    <span>{day.getDate()}</span>
                    {dayEvents.length > 0 && <strong>{dayEvents.length}</strong>}
                  </div>
                  <div className="public-events-calendar__items">
                    {dayEvents.slice(0, 3).map((event) => (
                      <Link key={event.id} to={`/events/${event.id}`}>
                        <span>{new Intl.DateTimeFormat('en', { hour: 'numeric', minute: '2-digit' }).format(toEventDate(event))}</span>
                        {event.title}
                      </Link>
                    ))}
                    {dayEvents.length > 3 && <em>+{dayEvents.length - 3} more</em>}
                  </div>
                </div>
              )
            })}
          </div>
          <div className="public-events-calendar__agenda">
            <div className="public-events-calendar__agenda-title">
              <ListChecks size={16} />
              <strong>{getMonthLabel(calendarMonth)} agenda</strong>
            </div>
            {monthEvents.length === 0 ? (
              <p>No matching events are currently scheduled for this month.</p>
            ) : (
              monthEvents.map((event) => (
                <Link key={event.id} to={`/events/${event.id}`} className="public-events-calendar__agenda-row">
                  <span>{getDayLabel(toEventDate(event))}</span>
                  <strong>{event.title}</strong>
                  <em>{event.venue}, {event.city}</em>
                  <ArrowRight size={14} />
                </Link>
              ))
            )}
          </div>
        </section>
      ) : (
        <div className="event-grid event-grid--public event-grid--editorial">
          {filtered.map((event) => {
            const { day, month } = getDateParts(event.startAt)
            return (
              <Link
                key={event.id}
                to={`/events/${event.id}`}
                className="event-card event-card--public event-card--editorial"
              >
                <div className="event-card__cover">
                  {event.coverImageUrl ? (
                    <img src={event.coverImageUrl} alt={event.title} />
                  ) : (
                    <div className={`event-card__mood event-card__mood--${event.mood}`} />
                  )}
                  <div className="event-card__date-badge">
                    <span className="event-card__date-badge-day">{day}</span>
                    <span className="event-card__date-badge-month">{month}</span>
                  </div>
                  <span className="event-card__status">{getDemandLabel(event)}</span>
                </div>
                <div className="event-card__body">
                  <div className="event-card__meta-line">
                    <span>
                      <CalendarDays size={13} />
                      {formatDateTime(event.startAt)}
                    </span>
                    <span>{getPriceLabel(event)}</span>
                  </div>
                  <h3 className="event-card__title">{event.title}</h3>
                  <p className="event-card__venue">
                    <MapPin size={14} />
                    {event.venue}, {event.city}
                  </p>
                  <div className="event-card__footer">
                    <span>{getTicketAvailability(event)}</span>
                    <span className="event-card__cta">
                      {getCtaLabel(event) === 'Get tickets' ? 'Book now' : getCtaLabel(event)}
                      <ArrowRight size={14} />
                    </span>
                  </div>
                </div>
              </Link>
            )
          })}
        </div>
      )}
    </div>
  )
}
