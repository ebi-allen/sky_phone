# Sky Phone 1.3.0

## Changes

- Add an optional radio HUD roster that keeps connected channel members visible. Configure separate primary and secondary talking colors; silent members stay gray. The existing talk-only mode remains the default. PMA Voice and SaltyChat now supply speaker highlights alongside Yaca.
- Keep radio rosters consistent when joining, saving configuration, disconnecting or switching channels. Ignore late configuration refreshes from an old connection and retain the correct SaltyChat channel color when another transmission ends.
- Add personal Phonepanel size controls from 80% to 160%. The percentage button resets to 100%; the local NUI cache remembers the preference without saving server settings or discarding configuration drafts.
- Add the optional TK Housing provider for personally owned properties and individual keys, entrance waypoints, permission-based door locking and key management. The server checks permissions and recipients again before each mutation. Motel restrictions remain enforced; CCTV, garage counts and membership-only job/business properties are unavailable through this provider.
- Restore Sky Cloud sign-in inside Flare after logout, including the existing profile, likes and matches. Keep complete English and German onboarding photo-button labels inside their controls.
- Add the new radio and Phonepanel labels to all sixteen bundled locales. Update Vite to 7.3.7, DOMPurify to 3.4.17 and the development dependency patches, retaining the lockfile security overrides and matching third-party notices.

## Update instructions

These steps cover upgrading from 1.2.1. For older installations, also apply the intervening release instructions.

1. Back up the resource and database. Preserve configuration, translations, server peppers, hooks and custom files, including custom sounds under `source/html/sounds`.
2. Stop resources registering Phone apps, then stop `sky_phone`. Use **sky_phone-1.3.0.zip**, keeping the folder named `sky_phone`. Replace `fxmanifest.lua`, `SOURCE.txt`, `RELEASE_NOTES.md`, `THIRD_PARTY_NOTICES.md` and the complete `source/` directory, then restore custom files. Install the rebuilt NUI and Lua together.
3. In Lua file mode, merge the new `Config.Radio.Hud` keys: `AlwaysShowMembers = false`, `PrimaryTalkColor = "#4ade80"` and `SecondaryTalkColor = "#facc15"`. Colors use `#RRGGBB`. In SQL mode, review them under **Phonepanel -> Phone configurator -> Radio -> Hud**; missing fields receive defaults while saved values are preserved. The linger duration applies only to talk-only mode.
4. TK Housing is optional. Start a version exposing the documented [server exports](https://tk-scripts.gitbook.io/docs/tk_housing/exports/server) before the phone, then select `tk_housing` in the active Housing configuration. Fresh automatic priorities include it last; existing saved priorities retain their order, so explicitly select it or add it to your priority list when needed. No other housing server needs to change providers.
5. Merge the new radio HUD and Phonepanel size entries from every language you maintain in `config/locales/`. Keep the English fallback installed. The personal size controls are in the Phonepanel header and require no server configuration.
6. Run `refresh`, start `sky_phone`, then start app resources in their normal order. Check your configured voice provider, channel changes, Flare sign-in and Phonepanel size controls. TK Housing users should also check owner/keyholder permissions, motel restrictions and key grants/revocation.

There is no SQL schema migration, new inventory item, streamed asset change or mandatory framework/voice-provider upgrade. Existing public Phone APIs remain compatible. Source installations must use the updated lockfile with pnpm 10.33.0 and rebuild the frontend; published ZIP installations do not need Node.js or pnpm.

## Changed shipped files

Relative to the installed `sky_phone` directory:

- `fxmanifest.lua` - version 1.3.0.
- `SOURCE.txt` and `RELEASE_NOTES.md` - package provenance and these update instructions.
- `THIRD_PARTY_NOTICES.md` - patched DOMPurify notice inventory.
- `config/config.lua` - new radio HUD fields and the optional TK Housing selection/priority.
- `config/locales/*.lua` - radio HUD and personal Phonepanel size labels in all sixteen locales.
- `source/bridge/client/housing/tk_housing.lua` and `source/bridge/server/housing/tk_housing.lua` - new optional housing adapters.
- `source/client/radio.lua`, `source/server/radio.lua`, `source/server/phone_configurator.lua` and `source/shared/config_default.lua` - radio state, validation and configuration defaults.
- `source/html/` - complete rebuilt NUI, locales and dependency bundles. Replace this directory as a unit and restore custom files afterward.

No files are removed or renamed outside the rebuilt NUI bundle. Frontend source, tests and repository documentation are outside the deployable resource.

Included pull requests: [#144](https://github.com/sky-systems/sky_phone/pull/144), [#145](https://github.com/sky-systems/sky_phone/pull/145), [#147](https://github.com/sky-systems/sky_phone/pull/147), [#148](https://github.com/sky-systems/sky_phone/pull/148), [#149](https://github.com/sky-systems/sky_phone/pull/149).
