import { ImagePlus, Trash2, Upload, UploadCloud } from 'lucide-react'
import type { ChangeEvent } from 'react'

import type { PortalPlace } from '../../lib/types'

type MediaPanelProps = {
  selectedPlace: PortalPlace | null
  selectedGalleryUrls: string[]
  coverUploading: boolean
  galleryUploading: boolean
  coverInputId: string
  coverReplaceId: string
  galleryInputId: string
  handleCoverUpload: (e: ChangeEvent<HTMLInputElement>) => void
  handleGalleryUpload: (e: ChangeEvent<HTMLInputElement>) => void
  removeGalleryImage: (url: string) => void
  savePlaceMedia: (media: { coverUrl?: string; galleryUrls?: string[] }) => Promise<void>
}

export function MediaPanel({
  selectedPlace,
  selectedGalleryUrls,
  coverUploading,
  galleryUploading,
  coverInputId,
  coverReplaceId,
  galleryInputId,
  handleCoverUpload,
  handleGalleryUpload,
  removeGalleryImage,
  savePlaceMedia,
}: MediaPanelProps) {
  return (
    <article className="panel">
      <div className="panel__header">
        <div>
          <p className="eyebrow">Photos</p>
          <h3>Cover & gallery</h3>
        </div>
        <ImagePlus size={22} aria-hidden />
      </div>
      {!selectedPlace ? (
        <div className="empty-card">
          <h4>Create the place first</h4>
          <p>Save a place profile to upload its cover image and gallery photos.</p>
        </div>
      ) : (
        <>
          <p className="text-subtle">Cover image</p>
          <div className="cover-upload-area">
            {selectedPlace.coverUrl ? (
              <div className="cover-upload-preview">
                <img src={selectedPlace.coverUrl} alt={`${selectedPlace.name} cover`} />
                <div className="cover-upload-preview__actions">
                  <label className="button button--secondary cover-upload-btn" htmlFor={coverReplaceId}>
                    <Upload size={15} aria-hidden />
                    {coverUploading ? 'Uploading…' : 'Replace cover'}
                    <input
                      accept="image/*"
                      disabled={coverUploading}
                      hidden
                      id={coverReplaceId}
                      onChange={handleCoverUpload}
                      type="file"
                    />
                  </label>
                  <button
                    className="button button--ghost"
                    disabled={coverUploading}
                    onClick={() => void savePlaceMedia({ coverUrl: '' })}
                    type="button"
                  >
                    <Trash2 size={15} aria-hidden />
                    Remove
                  </button>
                </div>
              </div>
            ) : (
              <label
                aria-label="Upload place cover image"
                className={`cover-upload-drop${coverUploading ? ' cover-upload-drop--uploading' : ''}`}
                htmlFor={coverInputId}
              >
                <div className="cover-upload-drop__inner">
                  <span className="cover-upload-drop__icon" aria-hidden>
                    <ImagePlus size={22} />
                  </span>
                  <strong>{coverUploading ? 'Uploading…' : 'Upload cover image'}</strong>
                  <span>JPG, PNG or WebP · 16:9 recommended</span>
                </div>
                <input
                  accept="image/*"
                  disabled={coverUploading}
                  hidden
                  id={coverInputId}
                  onChange={handleCoverUpload}
                  type="file"
                />
              </label>
            )}
          </div>
          <p className="text-subtle">Gallery</p>
          <div className="partner-feature-grid">
            {selectedGalleryUrls.length === 0 ? (
              <div className="empty-card">
                <h4>No gallery photos yet</h4>
                <p>Add photos of your space, crowd, and menu to bring your profile to life.</p>
              </div>
            ) : (
              selectedGalleryUrls.map((url) => (
                <div className="cover-upload-preview" key={url}>
                  <img src={url} alt="Gallery" />
                  <div className="cover-upload-preview__actions">
                    <button
                      className="button button--ghost"
                      onClick={() => void removeGalleryImage(url)}
                      type="button"
                    >
                      <Trash2 size={15} aria-hidden />
                      Remove
                    </button>
                  </div>
                </div>
              ))
            )}
          </div>
          <label className="button button--secondary cover-upload-btn" htmlFor={galleryInputId}>
            <UploadCloud size={15} aria-hidden />
            {galleryUploading ? 'Uploading…' : 'Add gallery photos'}
            <input
              accept="image/*"
              disabled={galleryUploading}
              hidden
              id={galleryInputId}
              multiple
              onChange={handleGalleryUpload}
              type="file"
            />
          </label>
        </>
      )}
    </article>
  )
}
