# TK Housing bridge

Set `Config.Housing.System = "tk_housing"`, or use automatic selection. Start
`tk_housing` before the phone. With Phone Configurator enabled, select the system
in its Housing settings; saved SQL priorities remain unchanged. No SQL migration
is needed. Use a TK Housing version providing the exports linked below.

The [server API](https://tk-scripts.gitbook.io/docs/tk_housing/exports/server)
provides property IDs, names, door coordinates, owners and individual keyholders.
The bridge lists personal ownership and explicitly assigned individual keys.
Public entrance access and job/business membership alone do not add properties.
`hasPropertyPermission` controls lock/key actions, including motel restrictions.
Granting requires an online recipient inside the property; revocation supports
offline holders and excludes the actor and owner. Mutations use the provider's
boolean result and are authorized again in the execute callback. Export failures
reach the existing callback error handler and its English diagnostic.

The generic phone client uses server coordinates for waypoints. The published
[client exports](https://tk-scripts.gitbook.io/docs/tk_housing/exports/client)
therefore need no additional calls. CCTV and garage counts are unavailable through
this bridge. The existing housing store reloads after mutations and when reopened.

## Cfx source verification

Inspected revision: `citizenfx/fivem@0d8a2a6f78a9922445d8930305af82a7b1826980`.
This is not a verified match for the deployed artifact.

- [Lua exports documentation](https://docs.fivem.net/docs/scripting-manual/runtimes/lua/#using-exports)
  and [scheduler.lua](https://github.com/citizenfx/fivem/blob/0d8a2a6f78a9922445d8930305af82a7b1826980/data/shared/citizen/scripting/lua/scheduler.lua#L465):
  function references, MessagePack results, coroutine awaits, export lookup and stop invalidation.
  Exports execute on the caller's side, with no automatic network RPC.
- [GET_RESOURCE_STATE declaration](https://github.com/citizenfx/fivem/blob/0d8a2a6f78a9922445d8930305af82a7b1826980/ext/native-decls/GetResourceState.md)
  and [ResourceScriptFunctions.cpp](https://github.com/citizenfx/fivem/blob/0d8a2a6f78a9922445d8930305af82a7b1826980/code/components/citizen-scripting-core/src/ResourceScriptFunctions.cpp#L278):
  shared, synchronous resource lookup with string argument/result, no out parameters.
- [SET_NEW_WAYPOINT metadata](https://github.com/citizenfx/fivem/blob/0d8a2a6f78a9922445d8930305af82a7b1826980/ext/natives/natives_stash/gta_21E43A33.lua#L38520)
  and [OAL binding generator](https://github.com/citizenfx/fivem/blob/0d8a2a6f78a9922445d8930305af82a7b1826980/ext/natives/codegen_out_native_lua.lua#L188):
  the existing client passes two separate floats; no return/out values. The GTA HUD
  implementation is proprietary; this verifies the binding, not an in-game result.

## Validation

From the repository root, run `lua5.4 tests/housing_tk.lua` and
`lua5.4 tests/phone_configurator.lua`. The tests use provider fixtures, not a running
TK installation. Live checks still require TK Housing: open the app as an owner and
keyholder, set a waypoint, toggle a lock, grant/revoke a key, then remove a permission
before executing a prepared action. Confirm that motel keys remain unavailable.
