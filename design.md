# WhatsFresh Design System

**Version:** 1.0  
**Last Updated:** 2026-04-28

---

## Design Tokens

### Colors

#### Primary
- `--color-primary`: `#0891b2` (Teal)
- `--color-primary-light`: `#dcfce7` (Light Teal)

#### Semantic
- `--color-success`: `#10b981` (Green)
- `--color-warning`: `#f59e0b` (Amber)
- `--color-error`: `#ef4444` (Red)
- `--color-accent`: `#f87171` (Coral)
- `--color-accent-light`: `#fb923c` (Light Orange)

#### Background
- `--color-bg-base`: `#ffffff` (White)
- `--color-bg-light`: `#f0fdf4` (Mint)
- `--color-bg-pale-pink`: `#fce7f3` (Pale Pink)
- `--color-bg-pale-blue`: `#e0f2fe` (Pale Blue)

#### Text
- `--color-text-primary`: `#1f2937` (Dark Gray)
- `--color-text-secondary`: `#6b7280` (Medium Gray)
- `--color-border`: `#d1d5db` (Light Gray)

### Typography

#### Font Family
- `--font-family-base`: `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif`

#### Font Sizes
- `--font-size-xs`: `12px`
- `--font-size-sm`: `14px`
- `--font-size-base`: `14px`
- `--font-size-lg`: `16px`
- `--font-size-xl`: `18px`
- `--font-size-2xl`: `24px`

#### Line Heights
- `--line-height-tight`: `1.4`
- `--line-height-base`: `1.6`
- `--line-height-loose`: `1.8`

#### Font Weights
- `--font-weight-normal`: `400`
- `--font-weight-medium`: `500`
- `--font-weight-semibold`: `600`
- `--font-weight-bold`: `700`

### Spacing

- `--gap-xs`: `4px`
- `--gap-sm`: `8px`
- `--gap-base`: `16px`
- `--gap-lg`: `24px`
- `--gap-xl`: `32px`

### Borders & Radius

- `--radius-sm`: `4px`
- `--radius-base`: `8px`
- `--radius-lg`: `12px`
- `--border-width`: `1px`

### Shadows

- `--shadow-sm`: `0 1px 2px 0 rgba(0, 0, 0, 0.05)`
- `--shadow-base`: `0 1px 3px 0 rgba(0, 0, 0, 0.1)`
- `--shadow-lg`: `0 10px 15px -3px rgba(0, 0, 0, 0.1)`

---

## Base Components

### Table

```css
table {
  width: 100%;
  border-collapse: collapse;
  background-color: var(--color-bg-base);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-base);
  overflow: hidden;
  font-size: var(--font-size-sm);
  table-layout: fixed;
}

th {
  background-color: var(--color-bg-light);
  padding: 4px var(--gap-sm);
  text-align: left;
  font-weight: var(--font-weight-semibold);
  color: var(--color-text-primary);
  border-bottom: var(--border-width) solid var(--color-border);
  text-transform: uppercase;
  letter-spacing: 0.5px;
  font-size: var(--font-size-xs);
  white-space: normal;
  overflow-wrap: break-word;
}

td {
  padding: 4px var(--gap-sm);
  border-bottom: var(--border-width) solid var(--color-border);
  color: var(--color-text-primary);
  white-space: normal;
  overflow-wrap: break-word;
}

tr:hover td {
  background-color: var(--color-bg-light);
}

.table.full { width: 100%; }
.table.half { width: 50%; }
.table.third { width: 33%; }
.table.tight { width: 300px; }
```

### Form Elements

```css
input, select, textarea {
  font-family: var(--font-family-base);
  font-size: var(--font-size-base);
  padding: var(--gap-sm) var(--gap-base);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-base);
  background-color: var(--color-bg-base);
  color: var(--color-text-primary);
  transition: border-color 0.2s;
}

input:focus, select:focus, textarea:focus {
  outline: none;
  border-color: var(--color-primary);
  box-shadow: 0 0 0 3px rgba(8, 145, 178, 0.1);
}
```

### Buttons

```css
button {
  font-family: var(--font-family-base);
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-medium);
  padding: var(--gap-sm) var(--gap-lg);
  border: none;
  border-radius: var(--radius-base);
  background-color: var(--color-primary);
  color: white;
  cursor: pointer;
  transition: background-color 0.2s;
}

button:hover {
  background-color: var(--color-primary-light);
}
```

### Sidebar

```css
.sidebar {
  width: 220px;
  background: #f9fafb;
  border-right: 1px solid #e5e7eb;
  padding: 12px 0;
  font-family: var(--font-family-base);
}

.sidebar .section-title {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: #888;
  padding: 8px 16px 4px;
  font-weight: var(--font-weight-semibold);
}

.sidebar a {
  display: block;
  padding: 6px 16px;
  color: #333;
  text-decoration: none;
  font-size: var(--font-size-sm);
}

.sidebar a:hover {
  background: #e5e7eb;
}

.sidebar a.active {
  background: var(--color-primary-light);
  color: var(--color-success);
  font-weight: var(--font-weight-semibold);
}
```

### Report Header

```css
.report {
  margin: 0;
  background: white;
  overflow: hidden;
  position: relative;
}

.header {
  background: var(--color-primary-light);
  color: var(--color-text-primary);
  padding: 20px 24px;
}

.header-bar {
  display: flex;
  align-items: center;
  gap: var(--gap-base);
}

.wf-icon {
  height: 40px;
  flex-shrink: 0;
}

.header-center {
  flex: 1;
  text-align: center;
}

.header-center h1 {
  font-size: var(--font-size-xl);
  margin: 0;
}

.desc {
  font-size: var(--font-size-sm);
  color: #555;
  margin-top: 4px;
}

.header-right {
  flex-shrink: 0;
  text-align: right;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: var(--gap-xs);
}

.generated {
  font-size: var(--font-size-xs);
  color: #888;
}

.header-meta {
  display: flex;
  gap: var(--gap-base);
  align-items: flex-start;
  margin-top: 14px;
  justify-content: center;
}

.info-card {
  flex: 1;
  text-align: center;
}

.info-card .label {
  font-size: var(--font-size-xs);
  text-transform: uppercase;
  color: #888;
  letter-spacing: 0.5px;
}

.info-card .value {
  font-size: var(--font-size-sm);
  font-weight: var(--font-weight-semibold);
  color: #333;
  margin-top: 2px;
}

.section {
  padding: var(--gap-base) 24px;
}

.section h2 {
  font-size: 15px;
  color: var(--color-text-primary);
  margin: 0 -24px 10px -24px;
  padding: 10px 24px;
  background: var(--color-primary);
  border-bottom: 2px solid var(--color-accent);
}

.subject {
  font-size: var(--font-size-lg);
  font-weight: var(--font-weight-semibold);
  color: #990000;
  margin-top: 4px;
}

.print-btn {
  background: rgba(0,0,0,0.08);
  color: #333;
  border: 1px solid rgba(0,0,0,0.15);
  padding: 6px 12px;
  border-radius: var(--radius-sm);
  cursor: pointer;
  font-size: var(--font-size-xs);
}

.print-btn:hover {
  background: rgba(0,0,0,0.14);
}

@media print {
  body { padding: 0; background: white; }
  .report { box-shadow: none; }
  .print-btn { display: none; }
}
```

---

## Usage

All components reference design tokens via CSS variables (`var(--color-primary)`, `var(--gap-base)`, etc.).

**For variants/overrides**, store in `studio.css` table with class-specific customizations only.

**For new components**, define base styles here, then extend with `studio.css` as needed.
