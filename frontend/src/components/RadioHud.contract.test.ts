import { readFileSync } from 'node:fs'

import { describe, expect, it } from 'vitest'

const source = readFileSync(
  new URL('./RadioHud.vue', import.meta.url),
  'utf8',
).replace(/\r\n/g, '\n')
const client = readFileSync(
  new URL('../../../sky_phone/source/client/radio.lua', import.meta.url),
  'utf8',
).replace(/\r\n/g, '\n')

describe('radio HUD roster contract', () => {
  it('keeps silent members only while always-show is on and paints them gray', () => {
    expect(source).toContain("state: 'idle' | 'recent' | 'talking'")
    expect(source).toContain('config.alwaysShowMembers')
    expect(source).toContain("state: 'idle'")
    expect(source).toContain("existing?.state === 'recent'")
    expect(source).toContain("if (entry.state === 'idle') removeEntry(id)")
    expect(source).toContain('rgb(214 214 214 / 82%)')
    expect(source).not.toContain('rgb(255 255 255 / 90%)')
    expect(source).toContain("entry.channel === 2 && entry.state === 'talking'")
  })

  it('accepts only #RRGGBB talking colors before they become CSS variables', () => {
    expect(source).toContain('const TALK_COLOR_PATTERN = /^#[\\da-f]{6}$/i')
    expect(source).toContain("'--radio-hud-primary': config.primaryTalkColor")
    expect(source).toContain(
      "'--radio-hud-secondary': config.secondaryTalkColor",
    )
    expect(source).toContain('var(--radio-hud-primary, #4ade80)')
    expect(source).toContain('var(--radio-hud-secondary, #facc15)')
    expect(client).toContain(
      'alwaysShowMembers = hud.AlwaysShowMembers == true',
    )
    expect(client).toContain('value:match("^#%x%x%x%x%x%x$")')
    expect(client).toContain(
      'primaryTalkColor = hud_color(hud.PrimaryTalkColor, "#4ade80")',
    )
    expect(client).toContain(
      'secondaryTalkColor = hud_color(hud.SecondaryTalkColor, "#facc15")',
    )
    expect(client.indexOf('local function send_hud_members()')).toBeLessThan(
      client.indexOf('sky_phone:configurator:updated'),
    )
    expect(client.indexOf('local function request(')).toBeLessThan(
      client.indexOf('sky_phone:configurator:updated'),
    )
    const handler = client.slice(
      client.indexOf('sky_phone:configurator:updated'),
    )
    expect(handler.indexOf('send_hud_config()')).toBeLessThan(
      handler.indexOf('set_hud_members(1, result.data.members)'),
    )
    expect(client).toContain('pending_members[frequency] = data.members')
    expect(client).toContain('flush_pending_members()')
    expect(client).toContain('pma-voice:radioActive')
    expect(client).toContain('pma-voice:setTalkingOnRadio')
    expect(client).toContain('GetProvider() ~= "pma"')
    expect(client).toContain('SaltyChat_RadioChannelSender:')
    expect(client).toContain('tonumber(sender.ServerId)')
    expect(client).toContain('changed_key ~= key')
  })
})
