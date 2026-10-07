# borders: agent operating model

Adopted 6 October 2026 from local source and command inspection.
Keep overlay presentation and physical lighting coherent without coupling their identities or consent.

## Read by intent

Start with the local agent guide and build manifest. For domain or behavior
changes, follow the owners below, then the relevant contract/test. These
documents retain product detail and historical evidence:

- [README.md](../README.md)
- [docs/plans/n-borders-menubar-ring-light.md](plans/n-borders-menubar-ring-light.md)

## System ownership

| Owner | Responsibility |
| --- | --- |
| [Sources/BordersCore/](../Sources/BordersCore) | Configuration, geometry, command/socket and feedback policies |
| [Sources/NBorders/BorderEngine.swift](../Sources/NBorders/BorderEngine.swift) | WindowServer events and overlays |
| [Sources/NBorders/KeyLightStore.swift](../Sources/NBorders/KeyLightStore.swift) | Bonjour and physical-light HTTP state |
| [Sources/NBorders/KeyLightBrightnessFeedbackController.swift](../Sources/NBorders/KeyLightBrightnessFeedbackController.swift) | Opt-in camera feedback orchestration |

Intent selects the owning policy; that policy produces decisions or artifacts;
adapters perform effects; verification establishes the result. Change the
owner once and keep alternate surfaces on that same contract.

## Invariants

- Portable baseline never overwritten by UI.
- Camera feedback opt-in/local/bounded.
- Overlay off and physical light power are separate effects.
- Socket response is reported observed state, not proof of hardware illumination.

## Existing action interfaces

These are inspected command surfaces, not a report that they ran. Read current
help and recipes for arguments, dependencies and lifecycle hooks before use.
Examples containing placeholder paths or bracketed options are grammar.

| Command | Effects and evidence |
| --- | --- |
| `borders status` | Reads running app settings through /tmp/borders.sock; two-second client deadline |
| `borders off` | Hides overlays and persists mode; app remains resident |
| `make unit-test` | Pure core tests |
| `make keylight-hardware-test ARGS="--host elgato-key-light-air-6389.local"` | Explicit live physical-light test; device operations |
| `make mutation` | Mutation plan only |
| `make dev` | Replaces installed app and launches |

## Observe, verify and retain

Establish source revision, dirty state and relevant input identity before
choosing an action. Keep intended settings, cached artifacts and observed
runtime state distinct. An existing artifact is not a freshness or readiness
claim. Use the smallest deterministic fixture at the changed seam first;
expand to process, browser, device or deployment checks only when that
claim needs them. Record unavailable evidence explicitly.

Retain the command/configuration, source and input identity, result, limitation
and next discriminating check. Reuse evidence only while its relevant inputs
remain applicable. Promote a reproducible failure to a regression fixture,
a design decision to its owning document, and a repeated operator correction
to one concise guide rule. Keep private observations in private artifacts.

## Implemented plan for this pass

- [x] Map current source ownership and existing interfaces.
- [x] Make command effects and evidence limits discoverable.
- [x] Route agent work here and retain detailed product plans at their owners.

Acceptance: owner paths and document links resolve; current instructions
match inspected source; catalog hashes bind this context to the reviewed
bytes. This is documentation/control navigation acceptance. Product runtime
checks retain their own scope and are not certified by this pass.

## Executable local contract — 7 October 2026

`make test-domain` enters KeyLightTests and proves testUserBrightnessZeroMeansPowerOffAndSmallOnValuesUseTheVisibleMinimum. `make test-core` runs the full SwiftPM fixture suite. `make check-local` is the mandatory Lefthook pre-push gate and includes the existing full quality/build checks without installing or launching the resident app. Hardware, permissions and hosted app checks remain separate explicit actions.

Zero requests power-off. Positive values below5 clamp to5; higher values remain requested. Test both sides of the minimum: the previous exact5 assertion allowed max→min to survive and silently reduced every higher request.

The source-bound action/learning descriptor is [.agent/contract.json](../.agent/contract.json). A changed source or test invalidates the applicable lesson; re-run the named domain proof before retaining new guidance. Dependency resolution uses a seven-day cooldown for active update managers and uv tooling; existing locked app dependencies are retained.

Control-channel verification: `swift test --filter "SocketTimeoutTests|CommandChannelTests"` uses owned temporary Unix sockets. A timed-out or empty reply returns a typed refusal and a nonzero CLI result; it does not establish app state or command success. Refresh state after resolving the unresponsive peer. `make check-local` also exercises this regression and retains the full mutation gate.
