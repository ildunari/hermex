# Model/provider picker adversarial visual review

Review basis: the generated `unified-light.png` and `unified-dark.png` concept
rasters were compared side-by-side with fresh signed iPhone 17 Simulator captures
of the production SwiftUI sheet. The rasters remain direction-only; the simulator
is the acceptance artifact.

## Blockers found in the baseline and resolved

| Detail | Baseline failure | Implemented resolution |
| --- | --- | --- |
| Sheet height | Medium detent exposed roughly one model and made the hierarchy feel cramped. | Initial detent is 84% with Large still available; four live model rows are visible on iPhone 17. |
| Provider selection | Bright blue outline looked like an unstyled focus ring. | Restrained warm bronze border plus a check badge; selection is not color-only. |
| Provider thumbnails | Repeated generic tiles contained text initials and looked fabricated. | No text inside thumbnails. Vetted SVG marks are compiled into the asset catalog, with a quiet Hermex fallback only where no reviewed mark exists. |
| Provider names | Raw IDs such as `openai-codex` and `kimi-coding` leaked into presentation. | Human-readable local presentation names are resolved separately from immutable provider IDs. |
| Provider cards | Cards were short, visually dense, and clipped long names. | 102x94-point continuous cards, larger 38-point artwork, two-line labels, and model-count captions. |
| Model results | Individual rows resembled default list skeletons and lacked visual grouping. | One warm semantic surface with continuous corners, inset dividers, fixed selection/favorite targets, and stable 64-point rows. |
| Metadata | Exact model ID and provider name were redundantly concatenated while already scoped to one provider. | Scoped results show the exact model ID only. All-provider results add the human-readable provider presentation name without changing identity. |
| Custom model form | Permanent fields competed with discovery. | A quiet bottom action opens a separate native identity form with Exact Model ID and Provider ID kept independent. |

## Detail comparison after refinement

- Typography uses SwiftUI system styles and Dynamic Type rather than raster-matched
  fixed fonts. Title, section label, result title, model title, and metadata have
  distinct weight/contrast roles in both appearances.
- Search and All/Favorites/Recent remain native controls. The two filters are
  independent: model view changes do not select a provider, and provider scope
  does not select a model.
- The warm light canvas, warm dark canvas, surfaces, separators, and text reuse
  `ChatPalette` semantic roles. The bronze state color was chosen specifically to
  match the reference restraint without coupling this control to the user-selectable
  header color.
- OpenAI, Fireworks, and Kimi produce distinct silhouettes in the first viewport.
  The OpenAI/Codex mark is monochrome; the official Fireworks purple is preserved.
- The native long-press menu stays anchored to the provider card. VoiceOver has an
  explicit Edit Appearance action so context-menu discovery is not the only path.
- The editor presents human-readable display name separately from read-only,
  copyable Provider ID. Artwork actions cover Photos, Files, bundled automatic,
  deterministic fallback, and reset without touching connection credentials.
- Favorite stars have 44-point hit targets and do not select/dismiss the sheet.
  Model rows also retain a non-color selection symbol.
- No provider image URL is decoded from the server response and no provider logo
  network request occurs at runtime.

## Intentional deviations from the generated rasters

- The raster's decorative leading plus button was omitted because the persistent
  Add Custom Model action is clearer and avoids duplicate entry points.
- Exact model IDs remain visible because they are operationally important in a
  self-hosted multi-provider app. They are lower contrast and truncated in the
  middle rather than hidden or reconstructed from display names.
- Native iOS search, sheet chrome, segmented control, context menu, and Form are
  retained instead of custom-drawing raster facsimiles. This preserves platform
  accessibility, keyboard behavior, Dynamic Type, and future iOS adaptation.
- Provider cards scroll horizontally instead of forcing four equal-width cards;
  the live server currently exposes ten providers and the control must scale.

## Runtime evidence

- Light and dark before/after collages:
  `docs/design/screenshots/model-picker-before-after-light.png` and
  `docs/design/screenshots/model-picker-before-after-dark.png`.
- Native long-press menu and editor captures are exported from the passing
  `ModelPickerUITests/testProviderLongPressOffersAppearanceEditor` result bundle.
- The UI test asserts the provider's immutable ID remains visible in the editor.

No unresolved visual blocker remains from the baseline comparison. The remaining
review decision is product taste: whether to keep the exact model-ID metadata in
the primary list or reveal it only on demand.
