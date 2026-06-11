# MiMo Account Card Simplification Design

## Context

The current MiMo quota UI already has the right product boundary: MiMo stays inside the `额度` tab as a remote-entitlement provider group, and multi-account display is supported. The problem is the account presentation layer.

Today each MiMo account is rendered in two layers:

- an account header row
- a nested quota card under that row

That split introduces redundant labels such as `MiMo Account` and `账号额度`, wastes vertical space, and makes the visual hierarchy feel fragmented. In the reported two-account state, the card also fails the product goal of "minimal but complete": the user cannot scan two accounts as two equally complete units.

The product direction for this refinement is:

- keep the existing MiMo provider grouping
- keep the existing single-account vs multi-account aggregate rule
- remove non-informational labels
- turn each account into one compact, self-contained card

## Decisions

- The outer `MiMo` vendor group remains. It is the provider boundary and should not be removed.
- A vendor-level aggregate summary card is shown only when MiMo has more than one account. A single MiMo account continues to hide the aggregate card.
- Each MiMo account becomes one complete account card. The UI no longer renders a separate account title row above a nested quota card.
- The following labels are removed from the account UI:
  - `MiMo Account`
  - `账号额度`
- Each account card has exactly four information areas:
  - top-left: readable account identity, preferring email
  - top-right: plan-type pill, such as `Pro`
  - middle: quota amount and progress bar
  - bottom: `x% used` on the left and account status/time on the right
- If the primary identity is already readable enough, the card does not render a second subtitle line.

## Final Card Layout

Within one MiMo provider group, the display order is:

1. vendor title: `MiMo`
2. optional vendor aggregate summary card when account count > 1
3. one account card per MiMo account, in configured display order

Within one account card, the display order is:

1. identity row
   - left: email first
   - right: plan pill
2. quota metrics row
   - main detail text such as `1.05B / 49.35B tokens`
3. progress bar
4. footer row
   - left: used ratio such as `2% used`
   - right: account refresh status text

The account card is the full reading unit. A user should be able to understand one account's identity, plan, remaining usage context, and freshness without leaving that card.

## Identity Rules

The account title chooses the first readable value from this order:

1. `email`
2. `platformEmail`
3. `phone`
4. non-technical `displayName`
5. non-technical username

Technical numeric MiMo IDs and values shaped like `MiMo 897298966` must not be shown as account titles.

If no readable identity exists, the UI falls back to a neutral ordered label such as `账号 1`, `账号 2`, based on the display order within the MiMo group. This fallback is display-only and must not affect persistence or account IDs.

## Status Text Rules

The account card footer owns all freshness and availability wording. Status is not duplicated elsewhere in the card.

- `ready` shows `updated x min ago`
- `stale` shows `last success x min ago`
- `login required` shows `login required`
- `failed` with a cached successful snapshot is rendered as stale and shows `last success x min ago`
- `failed` without any usable snapshot does not pretend to be a normal quota card; it renders a compact failure state instead of a large error block

This keeps one stable location for account state while still distinguishing a normal refresh, cached fallback, and missing login state.

## Data and Rendering Boundaries

This refinement changes presentation only. It does not change MiMo quota truth, refresh triggers, persistence rules, or login acquisition.

- `QuotaManagementView` is responsible for rendering the new single-card account layout.
- `QuotaSummarySection` may still be reused for the vendor aggregate summary card, but it is no longer the primary building block inside each MiMo account card.
- `QuotaAccountReadModel` continues to assemble MiMo account display data from `MiMoAccount` plus `EntitlementSummarySnapshot`.
- `QuotaAccountReadModel` must additionally provide the normalized footer status text input needed for:
  - `updated x min ago`
  - `last success x min ago`
  - `login required`
  - compact failure fallback
- `MiMoQuotaService`, `EntitlementResolutionService`, snapshot persistence, and refresh scheduling stay unchanged.

## Testing

The implementation must prove the design through focused display-layer tests.

- read-model tests:
  - single MiMo account hides the vendor aggregate summary
  - multiple MiMo accounts show the vendor aggregate summary
  - account titles never expose `MiMo Account`
  - account titles never expose technical numeric MiMo IDs
  - fallback identity labels use ordered neutral labels when no readable identity exists
  - footer status text matches the `ready / stale / login required / failed-with-cache` rules
- view tests:
  - account cards no longer render `账号额度`
  - plan pill remains visible
  - account cards render one unified structure instead of header-row plus nested summary-card composition

## Out Of Scope

- changing MiMo refresh TTL or refresh entry points
- changing token-plan calculation logic
- changing schema v3 persistence
- adding balance cards
- changing non-MiMo providers
