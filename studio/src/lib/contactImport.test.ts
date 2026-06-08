import { describe, expect, it } from 'vitest'

import {
  createAudienceImportPreviewFromRows,
  parseAudienceTextImport,
} from './contactImport'

describe('contact import parser', () => {
  it('parses csv headers and consent columns', () => {
    const preview = parseAudienceTextImport(
      'Name,Email,Phone,Marketing consent,SMS consent\nAma Mensah,ama@example.com,+233241234567,yes,yes',
    )
    expect(preview.contacts).toHaveLength(1)
    expect(preview.contacts[0]).toMatchObject({
      displayName: 'Ama Mensah',
      email: 'ama@example.com',
      marketingConsent: true,
      smsConsent: true,
    })
  })

  it('handles semicolon-delimited files', () => {
    const preview = parseAudienceTextImport(
      'Name;Email;Phone;Consent\nKojo Boateng;kojo@example.com;+233501112222;true',
    )
    expect(preview.contacts[0].phone).toBe('+233501112222')
    expect(preview.contacts[0].marketingConsent).toBe(true)
  })

  it('falls back to loose text for pdf and ocr output', () => {
    const preview = parseAudienceTextImport('Akua Sarpong +233207777777 akua@example.com opted in')
    expect(preview.contacts).toHaveLength(1)
    expect(preview.contacts[0].displayName).toBe('Akua Sarpong')
    expect(preview.contacts[0].marketingConsent).toBe(true)
  })

  it('deduplicates by email or phone and tracks invalid rows', () => {
    const preview = parseAudienceTextImport(
      'Name,Email,Phone,Consent\nAma,ama@example.com,,yes\nAma Duplicate,ama@example.com,,yes\nBad Row,,,yes',
    )
    expect(preview.contacts).toHaveLength(1)
    expect(preview.duplicateCount).toBe(1)
    expect(preview.invalidCount).toBe(1)
  })

  it('supports explicit field mapping and extra list tags', () => {
    const preview = createAudienceImportPreviewFromRows(
      [
        ['Phone number', 'Full name', 'Opt in', 'Segment'],
        ['+233241234567', 'Ama Mensah', 'yes', 'Sponsors'],
      ],
      {
        displayName: 1,
        email: -1,
        phone: 0,
        marketingConsent: 2,
        smsConsent: 2,
        tags: 3,
      },
      { extraTags: ['December leads'] },
    )
    expect(preview.contacts[0].displayName).toBe('Ama Mensah')
    expect(preview.contacts[0].tags).toEqual(['Sponsors', 'December leads'])
  })
})
