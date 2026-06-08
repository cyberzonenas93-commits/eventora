import {
  BriefcaseBusiness,
  Church,
  GraduationCap,
  HeartPulse,
  Laptop,
  LockKeyhole,
  Megaphone,
  MoonStar,
  Music2,
  Palette,
  Plane,
  RadioTower,
  Sparkles,
  Trophy,
  UsersRound,
  Utensils,
  type LucideIcon,
} from 'lucide-react'

export type EventCategory = {
  id: string
  label: string
  shortLabel: string
  description: string
  keywords: string[]
  Icon: LucideIcon
}

export const EVENT_CATEGORIES: EventCategory[] = [
  { id: 'nightlife', label: 'Nightlife & Parties', shortLabel: 'Nightlife', description: 'Clubs, lounges, day parties, DJ nights, beach parties.', keywords: ['nightlife', 'club', 'party', 'after dark', 'lounge', 'vip'], Icon: MoonStar },
  { id: 'music_live', label: 'Music & Live Entertainment', shortLabel: 'Music', description: 'Concerts, comedy, theatre, poetry, screenings.', keywords: ['music', 'concert', 'comedy', 'theatre', 'poetry', 'film'], Icon: Music2 },
  { id: 'corporate_professional', label: 'Corporate & Professional', shortLabel: 'Corporate', description: 'Conferences, networking, retreats, seminars, launches.', keywords: ['corporate', 'professional', 'conference', 'networking'], Icon: BriefcaseBusiness },
  { id: 'marketing_sales', label: 'Marketing & Sales', shortLabel: 'Marketing', description: 'Activations, pop-ups, trade shows, expos, retail sales.', keywords: ['marketing', 'sales', 'activation', 'pop-up', 'expo', 'retail'], Icon: Megaphone },
  { id: 'faith_spiritual', label: 'Faith & Spiritual', shortLabel: 'Faith', description: 'Church events, worship nights, crusades, retreats.', keywords: ['faith', 'church', 'worship', 'spiritual', 'crusade'], Icon: Church },
  { id: 'education_workshops', label: 'Education & Workshops', shortLabel: 'Workshops', description: 'Classes, bootcamps, masterclasses, trainings, lectures.', keywords: ['education', 'workshop', 'class', 'bootcamp', 'training'], Icon: GraduationCap },
  { id: 'food_drink', label: 'Food & Drink', shortLabel: 'Food', description: 'Brunches, tastings, chef nights, restaurant events.', keywords: ['food', 'drink', 'brunch', 'dinner', 'wine', 'tasting'], Icon: Utensils },
  { id: 'arts_culture_fashion', label: 'Arts, Culture & Fashion', shortLabel: 'Culture', description: 'Exhibitions, fashion shows, cultural festivals.', keywords: ['art', 'arts', 'culture', 'fashion', 'gallery', 'festival'], Icon: Palette },
  { id: 'sports_fitness', label: 'Sports & Fitness', shortLabel: 'Sports', description: 'Tournaments, screenings, runs, yoga, wellness events.', keywords: ['sports', 'fitness', 'football', 'run', 'yoga', 'match'], Icon: Trophy },
  { id: 'community_civic', label: 'Community & Civic', shortLabel: 'Community', description: 'Town halls, fundraisers, volunteer drives, local gatherings.', keywords: ['community', 'civic', 'charity', 'fundraiser', 'meetup'], Icon: UsersRound },
  { id: 'family_kids', label: 'Family & Kids', shortLabel: 'Family', description: 'School events, family fun days, kids activities.', keywords: ['family', 'kids', 'children', 'school', 'family friendly'], Icon: Sparkles },
  { id: 'lifestyle_wellness', label: 'Lifestyle & Wellness', shortLabel: 'Wellness', description: 'Beauty, health, self-care, and lifestyle socials.', keywords: ['lifestyle', 'wellness', 'beauty', 'health', 'self-care'], Icon: HeartPulse },
  { id: 'tech_startup', label: 'Tech & Startup', shortLabel: 'Tech', description: 'Hackathons, demo days, meetups, pitch events.', keywords: ['tech', 'startup', 'hackathon', 'demo day', 'pitch'], Icon: Laptop },
  { id: 'travel_experiences', label: 'Travel & Experiences', shortLabel: 'Travel', description: 'Tours, retreats, adventure trips, destination events.', keywords: ['travel', 'tour', 'retreat', 'trip', 'destination'], Icon: Plane },
  { id: 'private_invite', label: 'Private / Invite-Only', shortLabel: 'Private', description: 'Weddings, birthdays, company parties, private ticketing.', keywords: ['private', 'invite', 'wedding', 'birthday', 'invitation'], Icon: LockKeyhole },
  { id: 'online_hybrid', label: 'Online / Hybrid', shortLabel: 'Online', description: 'Webinars, livestreams, virtual and hybrid conferences.', keywords: ['online', 'hybrid', 'webinar', 'virtual', 'livestream'], Icon: RadioTower },
]

export const DEFAULT_EVENT_CATEGORY_ID = 'nightlife'

export function normalizeCategoryToken(value: string | null | undefined): string {
  return String(value ?? '')
    .trim()
    .toLowerCase()
    .replace(/&/g, 'and')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
}

export function canonicalCategoryId(value: string | null | undefined): string {
  const token = normalizeCategoryToken(value)
  if (!token || token === 'all') return DEFAULT_EVENT_CATEGORY_ID
  const direct = EVENT_CATEGORIES.find((category) =>
    token === category.id ||
    token === normalizeCategoryToken(category.label) ||
    token === normalizeCategoryToken(category.shortLabel) ||
    category.keywords.some((keyword) => token === normalizeCategoryToken(keyword)),
  )
  if (direct) return direct.id
  const aliases: Record<string, string> = {
    music: 'music_live',
    arts: 'arts_culture_fashion',
    business: 'corporate_professional',
    workshops: 'education_workshops',
    food_and_drink: 'food_drink',
    sports: 'sports_fitness',
    community: 'community_civic',
  }
  return aliases[token] ?? token
}

export function categoryById(value: string | null | undefined): EventCategory {
  const id = canonicalCategoryId(value)
  return EVENT_CATEGORIES.find((category) => category.id === id) ?? EVENT_CATEGORIES[0]
}

export function inferCategoryId(seed: {
  categoryId?: string | null
  category?: string | null
  title?: string | null
  description?: string | null
  mood?: string | null
  tags?: string[]
}): string {
  const direct = canonicalCategoryId(seed.categoryId || seed.category)
  if (EVENT_CATEGORIES.some((category) => category.id === direct)) return direct
  const text = [
    seed.title,
    seed.description,
    seed.mood,
    ...(seed.tags ?? []),
  ].filter(Boolean).join(' ').toLowerCase()
  return EVENT_CATEGORIES.find((category) => category.keywords.some((keyword) => text.includes(keyword)))?.id ?? DEFAULT_EVENT_CATEGORY_ID
}
