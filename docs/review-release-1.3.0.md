# Review and release evidence: 1.3.0

Reviewed 2026-10-27 against `dev` at `2c8aa1848bd7e17605be0f0edf209308ad3d6c29`.
Both the implementation and the repository contracts were checked for PRs
[#144](https://github.com/sky-systems/sky_phone/pull/144),
[#145](https://github.com/sky-systems/sky_phone/pull/145),
[#147](https://github.com/sky-systems/sky_phone/pull/147),
[#148](https://github.com/sky-systems/sky_phone/pull/148) and
[#149](https://github.com/sky-systems/sky_phone/pull/149).

## Findings resolved before integration

- **#144:** the lockfile omitted the manifest's overrides, preventing frozen
  installation and downgrading shell-quote to a vulnerable version. Commit
  `6cf62991fd904efb8021fb10e51790f941e7d3eb` restores those overrides and patches
  DOMPurify, Vitest, body-parser and qs. Matching source and packaged notices
  were regenerated. The final pnpm audit reports no known vulnerabilities.
- **#147:** a configuration refresh could return after disconnect or a channel
  change and restore an obsolete HUD roster. A regression failed on the original
  implementation. Commit `1f7d7bf68daf34aa0beb0d59e6eb9870b3e74a97` checks the
  connection generation and both frequencies after the yielding request. Tests
  cover forced disconnection, reconnection and an external Yaca frequency change.
  It also preserves the remaining SaltyChat transmission's channel color when
  an overlapping primary transmission ends.
- **#148:** commit `a1a126003fa20c72f3121b7b064d8f80dc81e760` keeps the new size
  controls' foreground white, as required by the workspace UI contract.
- **#145 and #149:** no additional actionable defects were found in the reviewed
  changes. TK mutations revalidate the selected provider, phone session, actor
  permission and target on the server. Flare reuses existing account authority.

## Combined validation

- Frozen pnpm 10.33.0 install, ESLint, TypeScript and notice checks passed.
- 262 frontend test files / 1,900 unit tests passed, together with license tests
  and the browser mock smoke suite.
- All 60 Edge browser cases passed, including app themes, Flare reauthentication,
  English/German photo controls, personal scale persistence and 160% layouts at
  1280x720, 1920x1080 and 2560x1440. Screenshots were inspected. Two completed
  local Playwright workers stalled during shutdown and were terminated; the
  runner then reported all 60 cases passed with exit code zero. GitHub's Linux
  CI provides independent checks of the original PRs and the release branch.
- Lua 5.4 compilation passed for 294 files; all 80 Lua test suites passed using
  `lupa.lua54`, including TK Housing, Configurator persistence and radio races.
- Repository validation and `git diff --check` passed.
- `build_frontend.bat` completed, including its required `build_copy.bat` step.
  All 576 files, including 321 generated NUI files, matched both configured local
  ESX and Qbox deployments by SHA-256.
- The previous published ZIP was inspected. After normalizing Windows line
  endings, changes outside generated NUI match the release's shipped-file list.
  There are no SQL or streamed-asset content changes.

## Runtime boundary

The local ESX server was refreshed and `sky_phone` restarted. It reports version
1.3.0 with experimental OAL enabled. Configurator initialization and database
startup completed without a captured script exception. Qbox was copied and
hash-checked; its runtime was not started by this task.

The connected FiveM client closed before the final client checks. The post-restart
client export call reported `player not connected` and local CEF was unavailable.
This is server startup evidence, not live NUI acceptance. TK Housing and SaltyChat
were not installed locally; their integration checks use documented contracts and
fixtures. Multiplayer voice behavior and full provider acceptance remain pending.

## Reproducible API evidence

- [TK server exports](https://tk-scripts.gitbook.io/docs/tk_housing/exports/server)
  were checked for property/keyholder shapes, actor-first permission arguments,
  recipient presence, motel restrictions and mutation return values.
- Cfx revision `0d8a2a6f78a9922445d8930305af82a7b1826980` was inspected; it is not
  asserted to match the installed artifact. In
  `code/components/citizen-scripting-core/src/ResourceScriptFunctions.cpp`,
  `ADD_STATE_BAG_CHANGE_HANDLER` registers exact bag/key filters, forwards values
  through the function reference and removes its cookie on resource stop;
  `REMOVE_STATE_BAG_CHANGE_HANDLER` consumes that cookie. The corresponding
  `ext/native-decls/*.md` declarations confirm shared execution, argument types
  and the callback signature, without pointer/out parameters.
- `data/shared/citizen/scripting/lua/scheduler.lua` supplies event registration,
  coroutine-aware export calls and `GlobalState = NewStateBag('global')`.
  The [Lua API documentation](https://docs.fivem.net/docs/scripting-manual/runtimes/lua/)
  and [state-bag documentation](https://docs.fivem.net/docs/scripting-manual/networking/state-bags/)
  were checked alongside those paths.
- The installed PMA Voice client/server radio handlers were inspected for
  `pma-voice:radioActive` and `pma-voice:setTalkingOnRadio` argument and sender
  behavior. These HUD signals do not authorize gameplay mutations.
