import { Plus, Utensils } from 'lucide-react'
import type { FormEvent } from 'react'

import { formatMoney } from '../../lib/formatters'
import type { PortalPlaceMenuItem, PortalPlaceMenuSection } from '../../lib/types'

type MenuTabProps = {
  sections: PortalPlaceMenuSection[]
  items: PortalPlaceMenuItem[]
  selectedPlaceId: string
  saving: boolean
  sectionName: string
  setSectionName: (value: string) => void
  sectionDescription: string
  setSectionDescription: (value: string) => void
  createSection: (e: FormEvent) => void
  itemSectionId: string
  setItemSectionId: (value: string) => void
  itemName: string
  setItemName: (value: string) => void
  itemPrice: string
  setItemPrice: (value: string) => void
  itemDescription: string
  setItemDescription: (value: string) => void
  itemFeatured: boolean
  setItemFeatured: (value: boolean) => void
  createItem: (e: FormEvent) => void
}

export function MenuTab({
  sections,
  items,
  selectedPlaceId,
  saving,
  sectionName,
  setSectionName,
  sectionDescription,
  setSectionDescription,
  createSection,
  itemSectionId,
  setItemSectionId,
  itemName,
  setItemName,
  itemPrice,
  setItemPrice,
  itemDescription,
  setItemDescription,
  itemFeatured,
  setItemFeatured,
  createItem,
}: MenuTabProps) {
  return (
    <article className="panel">
      <div className="panel__header">
        <div>
          <p className="eyebrow">Menu builder</p>
          <h3>Publish menu items</h3>
        </div>
        <Utensils size={22} aria-hidden />
      </div>
      <form className="form-grid" onSubmit={createSection}>
        <label>
          <span>Section name</span>
          <input value={sectionName} onChange={(e) => setSectionName(e.target.value)} required />
        </label>
        <label>
          <span>Description</span>
          <input value={sectionDescription} onChange={(e) => setSectionDescription(e.target.value)} />
        </label>
        <button className="button button--secondary" disabled={!selectedPlaceId || saving} type="submit">
          <Plus size={16} aria-hidden />
          Add section
        </button>
      </form>
      <form className="form-grid" onSubmit={createItem}>
        <label>
          <span>Section</span>
          <select value={itemSectionId} onChange={(e) => setItemSectionId(e.target.value)} required>
            <option value="">Choose section</option>
            {sections.map((section) => (
              <option key={section.id} value={section.id}>{section.name}</option>
            ))}
          </select>
        </label>
        <label>
          <span>Item name</span>
          <input value={itemName} onChange={(e) => setItemName(e.target.value)} required />
        </label>
        <label>
          <span>Price</span>
          <input inputMode="decimal" value={itemPrice} onChange={(e) => setItemPrice(e.target.value)} required />
        </label>
        <label>
          <span>Description</span>
          <input value={itemDescription} onChange={(e) => setItemDescription(e.target.value)} />
        </label>
        <label className="checkbox-row">
          <input checked={itemFeatured} onChange={(e) => setItemFeatured(e.target.checked)} type="checkbox" />
          <span>Feature item</span>
        </label>
        <button className="button button--primary" disabled={!itemSectionId || saving} type="submit">
          Publish item
        </button>
      </form>
      <div className="partner-feature-grid">
        {items.length === 0 ? (
          <div className="empty-card">
            <h4>No menu items yet</h4>
            <p>Create menu sections and publish drinks, food, bottles, or packages.</p>
          </div>
        ) : (
          items.map((item) => (
            <div className="partner-feature-card" key={item.id}>
              <strong>{item.name}</strong>
              <p>{item.description || item.status}</p>
              <small>{formatMoney(item.price)} · {sections.find((section) => section.id === item.sectionId)?.name || 'Menu'}</small>
            </div>
          ))
        )}
      </div>
    </article>
  )
}
