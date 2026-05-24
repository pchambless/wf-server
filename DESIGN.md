# WhatsFresh Design System

## Visual Theme

Clean, data-dense, light-mode application. Mint/teal accent on white. Compact spacing optimized for tabular data. No decorative elements — every pixel serves a function.

## Color Palette

| Token | Hex | Role |
|-------|-----|------|
| --color-primary | #0891b2 | Teal — links, focus rings, primary buttons |
| --color-primary-light | #dcfce7 | Light teal — hover states |
| --color-accent | #f87171 | Coral — alerts, destructive actions |
| --color-accent-light | #fb923c | Light orange — warnings |
| --color-success | #10b981 | Green — confirmations |
| --color-warning | #f59e0b | Amber — caution states |
| --color-error | #ef4444 | Red — errors, validation |
| --color-bg-base | #ffffff | White — cards, surfaces |
| --color-bg-light | #f0fdf4 | Mint — subtle backgrounds |
| --color-text-primary | #1f2937 | Dark gray — body text |
| --color-text-secondary | #6b7280 | Medium gray — labels, hints |
| --color-border | #d1d5db | Light gray — borders, dividers |

Body background: #f9fafb

## Typography

- Font: system stack (-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica Neue, Arial, sans-serif)
- Base size: 14px
- Line height: 1.6 (base), 1.4 (tight/headings), 1.8 (loose)
- Weights: 400 (normal), 500 (medium), 600 (semibold), 700 (bold)
- Headings: semibold, tight line-height
- h1: 24px, h2: 18px, h3: 16px

## Spacing Scale

| Token | Value |
|-------|-------|
| --gap-xs | 4px |
| --gap-sm | 8px |
| --gap-base | 16px |
| --gap-lg | 24px |
| --gap-xl | 32px |

## Borders & Radius

- Border width: 1px
- Radius: 4px (sm), 8px (base), 12px (lg)
- Border color: var(--color-border)

## Shadows

- sm: 0 1px 2px rgba(0,0,0,0.05)
- base: 0 1px 3px rgba(0,0,0,0.1)
- lg: 0 10px 15px -3px rgba(0,0,0,0.1)

## Component Patterns

### Appbar
- Flex row, vertically centered, 6px 14px padding
- Background: linear-gradient(135deg, #065f46, #0d9488)
- White text, no border
- Contains: icon, page title, account name, logout button

### Grid (data table)
- Wrapper classes: `page-grid grid-fixed grid-scroll grid-sticky`
- Max height: 62vh with overflow scroll
- Header: sticky, #e8f6ea background, 600 weight, 1px border
- Cells: 2px 6px padding, 1px border, top-aligned
- Row hover: #f4fbf4 background
- Alignment classes: col-left, col-center, col-right
- Use `<colgroup>` with percentage widths (total ~99%)
- Row click target: `<tr class="grid-row" data-row-id="{{id}}">`

### Search Input (grid filter)
- Placed above grid in `<div class="grid-search">`
- Filters rows client-side by text content

### Select / Dropdown
- Standard form element styling (padding, border, radius)
- Focus: teal border + subtle box-shadow

### Tabs
- Flex row with gap-lg
- Bottom border on container
- Active tab: primary color border-bottom

### Modal
- Hidden by default (display: none)
- Overlay pattern

### Buttons
- Primary: teal background, black text, 8px radius
- Padding: 8px 24px
- Hover: lighter background
- No border

## Layout

- Page structure: appbar → nav → content area
- Content fills available space below appbar
- Grids take percentage width (50-60% typical)
- Slots define component placement: `{{slot:name}}`

## Anti-patterns

- No inline styles except grid wrapper width
- No action JSON in template row markup (actions live in page_components.actions)
- No hardcoded data in templates (use {{field}} placeholders)
- No decorative gradients or shadows on data surfaces
- No custom fonts or icon libraries (system stack only)

## Grid Template Pattern

Reference: `wf-agents/docs/snippets/grid_html.txt`

Every grid follows this structure:
1. Search input div
2. Table wrapper with grid utility classes
3. Colgroup defining column widths
4. Thead with alignment classes
5. Tbody with `{{#each data}}` loop
6. Each row: `<tr class="grid-row" data-row-id="{{id}}">`

Actions are declared in `page_components.actions`, not in template HTML.
Client resolves `{{id}}` placeholders from `data-row-id` at click time.
