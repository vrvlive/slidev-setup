#!/usr/bin/env bash
#
# setup-slidev-skill.sh
#
# One-shot local setup: installs a Slidev toolchain and registers it as an
# Agent Skill for Google Antigravity.
#
# Usage:
#   ./setup-slidev-skill.sh                   # global: ~/.gemini/config/skills
#   ./setup-slidev-skill.sh --workspace       # install into ./.agents/skills
#   ./setup-slidev-skill.sh --workspace ~/p   # install into ~/p/.agents/skills
#   ./setup-slidev-skill.sh --global-dir DIR  # install into a custom skills root
#   ./setup-slidev-skill.sh --keep-warm       # keep template node_modules (~400MB)
#   ./setup-slidev-skill.sh --skip-verify     # skip the export smoke test
#
# Global installs go to ~/.gemini/config/skills (Antigravity 2.0). If the older
# ~/.gemini/antigravity/skills directory exists, a symlink is added there too.
#
# Everything runs locally. After setup, deck creation and export work offline.

set -euo pipefail

# ---------------------------------------------------------------- config ----

SKILL_NAME="slidev-deck"
# Antigravity 2.0 (v2.13+) reads global skills from ~/.gemini/config/skills.
# The older "Antigravity for IDEs" extension reads ~/.gemini/antigravity/skills.
# We install into the first and link into the second when it is present.
GLOBAL_SKILL_ROOT="$HOME/.gemini/config/skills"
LEGACY_SKILL_ROOT="$HOME/.gemini/antigravity/skills"
GLOBAL_SKILL_ROOT_OVERRIDE=""
SCOPE="global"
WORKSPACE_DIR="$PWD"
KEEP_WARM=0
SKIP_VERIFY=0
MIN_NODE_MAJOR=20

# ---------------------------------------------------------------- output ----

if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

step() { printf '%s==>%s %s%s%s\n' "$BLUE" "$RESET" "$BOLD" "$1" "$RESET"; }
info() { printf '    %s\n' "$1"; }
warn() { printf '%s !  %s%s\n' "$YELLOW" "$1" "$RESET"; }
ok()   { printf '%s ✓  %s%s\n' "$GREEN" "$1" "$RESET"; }
die()  { printf '%s ✗  %s%s\n' "$RED" "$1" "$RESET" >&2; exit 1; }

# ------------------------------------------------------------------ args ----

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace)
      SCOPE="workspace"
      if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then WORKSPACE_DIR="$2"; shift; fi
      ;;
    --global)      SCOPE="global" ;;
    --global-dir)
      [ $# -gt 1 ] || die "--global-dir needs a path"
      SCOPE="global"; GLOBAL_SKILL_ROOT_OVERRIDE="$2"; shift
      ;;
    --keep-warm)   KEEP_WARM=1 ;;
    --skip-verify) SKIP_VERIFY=1 ;;
    -h|--help)     sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

if [ -n "$GLOBAL_SKILL_ROOT_OVERRIDE" ]; then
  GLOBAL_SKILL_ROOT="$GLOBAL_SKILL_ROOT_OVERRIDE"
  LEGACY_SKILL_ROOT=""
fi

if [ "$SCOPE" = "global" ]; then
  SKILL_DIR="$GLOBAL_SKILL_ROOT/$SKILL_NAME"
else
  [ -d "$WORKSPACE_DIR" ] || die "Workspace not found: $WORKSPACE_DIR"
  SKILL_DIR="$WORKSPACE_DIR/.agents/skills/$SKILL_NAME"
fi

TEMPLATE_DIR="$SKILL_DIR/resources/template"
SCRIPTS_DIR="$SKILL_DIR/scripts"

# ------------------------------------------------------------- preflight ----

step "Checking prerequisites"

command -v node >/dev/null 2>&1 || die "Node.js not found. Install Node $MIN_NODE_MAJOR+ (https://nodejs.org or via nvm) and re-run."
command -v npm  >/dev/null 2>&1 || die "npm not found. It ships with Node.js — reinstall Node and re-run."

NODE_VERSION="$(node --version)"
NODE_MAJOR="$(printf '%s' "$NODE_VERSION" | sed 's/^v//' | cut -d. -f1)"
if [ "$NODE_MAJOR" -lt "$MIN_NODE_MAJOR" ]; then
  die "Node $NODE_VERSION found, but Slidev needs $MIN_NODE_MAJOR+. Upgrade and re-run."
fi
ok "Node $NODE_VERSION"
ok "npm $(npm --version)"

if [ -d "$SKILL_DIR" ]; then
  warn "Skill directory already exists: $SKILL_DIR"
  printf '    Overwrite it? [y/N] '
  read -r REPLY </dev/tty || REPLY="n"
  case "$REPLY" in
    [yY]*) rm -rf "$SKILL_DIR" ;;
    *)     die "Aborted. Nothing was changed." ;;
  esac
fi

# --------------------------------------------------------------- scaffold ----

step "Creating skill at $SKILL_DIR"
mkdir -p "$TEMPLATE_DIR/styles" "$TEMPLATE_DIR/components" "$TEMPLATE_DIR/public" \
         "$SCRIPTS_DIR" "$SKILL_DIR/references"

# ---- template: package.json -------------------------------------------------

cat > "$TEMPLATE_DIR/package.json" <<'PKG_EOF'
{
  "name": "deck",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "slidev --open",
    "build": "slidev build",
    "export": "slidev export --output dist/deck.pdf",
    "export:pptx": "slidev export --format pptx --output dist/deck.pptx",
    "snapshot": "slidev export --format png --output dist/review"
  },
  "dependencies": {
    "@slidev/cli": "latest",
    "@slidev/theme-default": "latest",
    "@slidev/theme-seriph": "latest"
  },
  "devDependencies": {
    "playwright-chromium": "latest"
  }
}
PKG_EOF

# ---- template: design tokens ------------------------------------------------

cat > "$TEMPLATE_DIR/styles/theme.css" <<'CSS_EOF'
/*
 * The single source of truth for this deck's look.
 * Change values here. Do NOT hardcode colours, sizes or fonts in slides.md.
 */

:root {
  /* Palette */
  --deck-bg:        #0f1117;
  --deck-surface:   #171a23;
  --deck-fg:        #e8eaf0;
  --deck-muted:     #98a0b3;
  --deck-accent:    #5b8cff;
  --deck-accent-2:  #ff7a59;
  --deck-border:    #272b38;

  /* Type scale */
  --deck-font-sans: "Inter", ui-sans-serif, system-ui, -apple-system, sans-serif;
  --deck-font-mono: "JetBrains Mono", ui-monospace, SFMono-Regular, monospace;
  --deck-title:     3.25rem;
  --deck-heading:   2.1rem;
  --deck-body:      1.15rem;
  --deck-small:     0.9rem;

  /* Rhythm */
  --deck-gap:       1.25rem;
  --deck-radius:    12px;
}

.slidev-layout {
  background: var(--deck-bg);
  color: var(--deck-fg);
  font-family: var(--deck-font-sans);
  font-size: var(--deck-body);
  line-height: 1.55;
}

.slidev-layout h1 { font-size: var(--deck-title);   font-weight: 700; letter-spacing: -0.02em; }
.slidev-layout h2 { font-size: var(--deck-heading); font-weight: 650; letter-spacing: -0.01em; }
.slidev-layout h1 + p { color: var(--deck-muted); opacity: 1; }

.slidev-layout a          { color: var(--deck-accent); text-decoration: none; border-bottom: 1px solid var(--deck-border); }
.slidev-layout code       { font-family: var(--deck-font-mono); }
.slidev-layout blockquote { border-left: 3px solid var(--deck-accent); color: var(--deck-muted); }
.slidev-layout li         { margin-block: 0.35em; }

/* Reusable helpers — prefer these over inline styles */
.muted   { color: var(--deck-muted); }
.accent  { color: var(--deck-accent); }
.kicker  { font-size: var(--deck-small); text-transform: uppercase; letter-spacing: 0.12em; color: var(--deck-muted); }
.card    { background: var(--deck-surface); border: 1px solid var(--deck-border);
           border-radius: var(--deck-radius); padding: var(--deck-gap); }
CSS_EOF

cat > "$TEMPLATE_DIR/styles/index.ts" <<'IDX_EOF'
// Slidev auto-loads styles/index.ts. Import additional stylesheets here.
import './theme.css'
IDX_EOF

# ---- template: starter slides ----------------------------------------------

cat > "$TEMPLATE_DIR/slides.md" <<'SLIDES_EOF'
---
theme: default
title: Deck Title
info: One-line description of this deck.
class: text-left
highlighter: shiki
lineNumbers: false
drawings:
  persist: false
transition: slide-left
mdc: true
fonts:
  sans: Inter
  mono: JetBrains Mono
---

# Deck Title

<p class="muted">Subtitle or one-sentence premise</p>

<div class="kicker mt-8">Your Name · Venue · 2026</div>

---
layout: section
---

# Section One

---

# A Content Slide

Keep it to one idea. Three bullets maximum.

- First point, stated plainly
- Second point
- Third point

<!--
Speaker notes live here. They show in presenter mode and export to PDF notes.
-->

---
layout: two-cols-header
---

# Comparison

::left::

## Before
<div class="card">Describe the old state.</div>

::right::

## After
<div class="card">Describe the new state.</div>

---

# Code

```ts {2-3|5}
function greet(name: string) {
  const greeting = `Hello, ${name}`;
  return greeting;
}

console.log(greet("world"));
```

---
layout: center
class: text-center
---

# Thank you

<p class="muted">questions@example.com</p>
SLIDES_EOF

# ---- template: misc ---------------------------------------------------------

cat > "$TEMPLATE_DIR/.gitignore" <<'GIT_EOF'
node_modules/
dist/
.slidev/
*.log
GIT_EOF

cat > "$TEMPLATE_DIR/components/.gitkeep" <<'EOF'
EOF
cat > "$TEMPLATE_DIR/public/.gitkeep" <<'EOF'
EOF

# ------------------------------------------------------------- helper scripts ----

step "Writing helper scripts"

cat > "$SCRIPTS_DIR/new-deck.sh" <<'NEW_EOF'
#!/usr/bin/env bash
# Scaffold a new Slidev deck from the skill template.
# Usage: new-deck.sh <target-dir> [ "Deck Title" ]
set -euo pipefail

SKILL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$SKILL_ROOT/resources/template"

if [ $# -lt 1 ]; then
  echo "Usage: new-deck.sh <target-dir> [ \"Deck Title\" ]" >&2
  exit 1
fi

TARGET="$1"
TITLE="${2:-Deck Title}"

[ -e "$TARGET" ] && { echo "Refusing to overwrite existing path: $TARGET" >&2; exit 1; }

mkdir -p "$TARGET"
# Copy everything except node_modules / dist
( cd "$TEMPLATE" && tar --exclude=node_modules --exclude=dist -cf - . ) | ( cd "$TARGET" && tar -xf - )

# Substitute the title
if [ -n "$TITLE" ]; then
  TMP="$TARGET/.slides.tmp"
  sed "s/^# Deck Title$/# ${TITLE//\//\\/}/; s/^title: Deck Title$/title: ${TITLE//\//\\/}/" \
    "$TARGET/slides.md" > "$TMP" && mv "$TMP" "$TARGET/slides.md"
fi

echo "Installing dependencies (offline where possible)..."
( cd "$TARGET" && npm install --prefer-offline --no-audit --no-fund --loglevel=error )

echo "Deck ready: $TARGET"
echo "  preview:  cd $TARGET && npm run dev"
echo "  snapshot: $SKILL_ROOT/scripts/snapshot.sh $TARGET"
NEW_EOF

cat > "$SCRIPTS_DIR/snapshot.sh" <<'SNAP_EOF'
#!/usr/bin/env bash
# Render every slide to PNG so the agent can LOOK at the deck.
# Usage: snapshot.sh [deck-dir]   (defaults to current directory)
set -euo pipefail

DECK="${1:-$PWD}"
cd "$DECK"

[ -f slides.md ] || { echo "No slides.md in $DECK" >&2; exit 1; }
[ -d node_modules ] || npm install --prefer-offline --no-audit --no-fund --loglevel=error

rm -rf dist/review
npx --no-install slidev export --format png --output dist/review slides.md

COUNT=$(find dist/review -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
echo "Rendered $COUNT slide image(s) to: $DECK/dist/review"
echo "View every one of them before reporting the deck as done."
SNAP_EOF

cat > "$SCRIPTS_DIR/export.sh" <<'EXP_EOF'
#!/usr/bin/env bash
# Export the deck.
# Usage: export.sh [deck-dir] [pdf|pptx|png]   (defaults: cwd, pdf)
set -euo pipefail

DECK="${1:-$PWD}"
FORMAT="${2:-pdf}"
cd "$DECK"

[ -f slides.md ] || { echo "No slides.md in $DECK" >&2; exit 1; }
[ -d node_modules ] || npm install --prefer-offline --no-audit --no-fund --loglevel=error

mkdir -p dist
case "$FORMAT" in
  pdf)  npx --no-install slidev export --output dist/deck.pdf slides.md ;;
  pptx) npx --no-install slidev export --format pptx --output dist/deck.pptx slides.md ;;
  png)  npx --no-install slidev export --format png --output dist/slides slides.md ;;
  *)    echo "Unknown format: $FORMAT (use pdf, pptx or png)" >&2; exit 1 ;;
esac

echo "Exported to $DECK/dist"
EXP_EOF

cat > "$SCRIPTS_DIR/preview.sh" <<'PREV_EOF'
#!/usr/bin/env bash
# Start the live dev server. Blocks until stopped — do not run this from an
# automated loop; use snapshot.sh instead.
# Usage: preview.sh [deck-dir]
set -euo pipefail

DECK="${1:-$PWD}"
cd "$DECK"
[ -d node_modules ] || npm install --prefer-offline --no-audit --no-fund --loglevel=error
npx --no-install slidev --open slides.md
PREV_EOF

chmod +x "$SCRIPTS_DIR"/*.sh

# ----------------------------------------------------------------- SKILL.md ----

step "Writing SKILL.md"

cat > "$SKILL_DIR/SKILL.md" <<'SKILL_EOF'
---
name: slidev-deck
description: Builds, edits and exports presentation decks locally with Slidev (Markdown + Vue), including a render-and-inspect loop that catches overflowing or ugly slides before handing the deck back. Use this skill whenever the user mentions slides, a deck, a presentation, a talk, a pitch, a keynote, or asks to turn a document, README or set of notes into something presentable — even if they never say the word "Slidev". Also use it for restyling an existing deck, fixing layout problems, or exporting to PDF or PPTX.
---

# Slidev Deck

Author decks as Markdown, render them locally, look at the rendered output, and fix
what looks wrong. Everything runs on this machine; nothing is uploaded.

## Decision tree

- **User wants a new deck** → run `scripts/new-deck.sh <dir> "Title"`, then edit `slides.md`.
- **User points at an existing deck** (a directory containing `slides.md`) → edit in place.
- **User has source material** (doc, README, notes) → read it first, write an outline as a
  bulleted list, confirm the outline with the user, *then* write slides.
- **User only wants a style change** → edit `styles/theme.css` only. Do not touch `slides.md`.
- **User wants an editable PowerPoint for a colleague** → warn them first: Slidev's PPTX
  export embeds each slide as an image, so it is not editable. Ask whether they want that
  anyway or would rather have a PDF.

## The loop that actually matters

Never report a deck as finished without having looked at the rendered slides.

1. Edit `slides.md`.
2. Run `scripts/snapshot.sh <deck-dir>` — renders every slide to PNG in `dist/review/`.
3. **Read each PNG image.** Check for: text running off the slide, overlapping elements,
   headings wrapping to three lines, code blocks with a scrollbar, near-empty slides,
   contrast that is too low to read.
4. Fix and repeat until every slide is clean.

Step 3 is the whole point. Source Markdown gives no indication of overflow — a slide that
looks fine in the editor is routinely broken when rendered. Skipping the visual check is
the single most common way this task fails.

Do not run `scripts/preview.sh` in an automated loop; it starts a blocking dev server.
Use it only when the user explicitly asks to view the deck live.

## Content rules

- One idea per slide. If a slide needs a paragraph of prose, it is two slides.
- Maximum ~40 words of body text per slide. Bullets: 3, ideally; 5, absolutely maximum.
- Bullets are fragments, not sentences. No terminal punctuation.
- Prefer a diagram, a table or a code block over another bulleted list.
- Put the detail in speaker notes (`<!-- ... -->` at the end of a slide), not on the slide.
- Never invent statistics, quotes or attributions to fill a slide.

## Style rules

- All colours, fonts and spacing come from CSS variables in `styles/theme.css`.
  Use `var(--deck-accent)` and the helper classes (`.muted`, `.accent`, `.kicker`, `.card`).
- Do **not** write hardcoded hex colours or font sizes into `slides.md`.
- To restyle a deck, change the variables in one place. That is the entire point of the file.
- Tailwind utility classes are available for layout (spacing, flex, grid). Use them for
  structure, not for colour.

## Slidev syntax essentials

Slides are separated by `---` on its own line. Per-slide options go in a YAML block
immediately after the separator:

```md
---
layout: two-cols
class: text-center
transition: fade
---
```

Useful built-in layouts: `default`, `center`, `cover`, `section`, `two-cols`,
`two-cols-header`, `image-right`, `image-left`, `quote`, `statement`, `fact`, `end`.
For `two-cols`, split content with `::right::`.

Other frequently useful pieces:

- Incremental reveal: `<v-click>...</v-click>` or `<v-clicks>` around a list.
- Code highlighting by step: ` ```ts {2-3|5} ` highlights lines 2-3, then line 5 on click.
- Diagrams: fenced ` ```mermaid ` blocks render natively.
- Images: put files in `public/` and reference them as `/filename.png`.
- Speaker notes: an HTML comment as the last element of a slide.

If you need syntax beyond this, read `references/slidev-cheatsheet.md` rather than guessing.

## Commands

Run these as black boxes; they handle dependency installation themselves.

| Task | Command |
|---|---|
| New deck | `scripts/new-deck.sh <dir> "Title"` |
| Render all slides to PNG | `scripts/snapshot.sh <dir>` |
| Export PDF | `scripts/export.sh <dir> pdf` |
| Export PPTX (images) | `scripts/export.sh <dir> pptx` |
| Live preview (blocking) | `scripts/preview.sh <dir>` |

## Troubleshooting

- **Export fails mentioning a browser or Playwright** → run
  `npx playwright install chromium` inside the deck directory.
- **A theme is missing** → `npm install @slidev/theme-<name>` in the deck directory.
  Do not switch themes without asking the user.
- **Port already in use** → another dev server is running; use `snapshot.sh` instead.
- **Fonts look wrong offline** → the `fonts:` key in the headmatter fetches webfonts on
  first run. Either connect once to cache them, or delete the `fonts:` block and rely on
  the system stack already defined in `styles/theme.css`.
SKILL_EOF

# ---------------------------------------------------------------- reference ----

cat > "$SKILL_DIR/references/slidev-cheatsheet.md" <<'REF_EOF'
# Slidev syntax reference

Read this only when the essentials in SKILL.md are not enough.

## Headmatter (first YAML block of slides.md)

| Key | Purpose |
|---|---|
| `theme` | Theme package, e.g. `default`, `seriph` |
| `title` | Deck title, used for exports and the browser tab |
| `info` | Description shown in presenter mode |
| `transition` | `slide-left`, `fade`, `slide-up`, `none` |
| `highlighter` | `shiki` (default) |
| `lineNumbers` | Show line numbers in code blocks |
| `mdc` | Enable MDC syntax (attributes on Markdown elements) |
| `fonts` | `sans`, `serif`, `mono` — fetched from Google Fonts on first build |
| `drawings.persist` | Persist annotations drawn during presenting |
| `download` | Offer a PDF download button in the built SPA |

## Per-slide frontmatter

| Key | Purpose |
|---|---|
| `layout` | Layout name |
| `class` | Tailwind classes applied to the slide root |
| `background` | Image URL or colour for `cover`/`image` layouts |
| `clicks` | Total click count for the slide |
| `transition` | Override the deck transition |
| `hide` | Skip this slide entirely |
| `zoom` | Scale slide content, e.g. `0.9` — useful for a slide that slightly overflows |

## Animation

```md
<v-click>Appears on first click</v-click>

<v-clicks>

- one
- two
- three

</v-clicks>

<v-click at="3">Appears on the third click</v-click>
```

`v-after` appears with the previous element. `v-mark` draws an annotation over text.

## Magic Move

Animates between two code snippets token by token:

````md
````md magic-move
```js
const a = 1
```
```js
const a = 1
const b = 2
```
````
````

## Layout notes

- `two-cols` — content before `::right::` goes left.
- `two-cols-header` — content before `::left::` becomes a full-width header.
- `image-right` / `image-left` — set `image: /path.png` in the slide frontmatter.
- `cover` / `section` — title slides; keep to a heading and one line.
- `quote`, `statement`, `fact` — single large element, no bullets.

## Custom components

Vue single-file components in `components/` are auto-imported and usable directly in
`slides.md` by filename. Build one only when a layout is needed on three or more slides.

## Export flags

| Flag | Effect |
|---|---|
| `--format pdf\|pptx\|png\|md` | Output format |
| `--output <path>` | Destination |
| `--with-clicks` | One page per click step rather than per slide |
| `--dark` | Export in dark mode |
| `--range 1,3-5` | Export a subset of slides |
| `--per-slide` | Render pages one at a time (slower, fixes some layout bugs) |

## Static site

`npm run build` produces a self-contained SPA in `dist/` that can be opened from the
filesystem or served from any static host.
REF_EOF

ok "Skill files written"

# ------------------------------------------------------------------ install ----

step "Installing Slidev toolchain (this downloads packages once)"
info "Target: $TEMPLATE_DIR"

if ( cd "$TEMPLATE_DIR" && npm install --no-audit --no-fund --loglevel=error ); then
  ok "Dependencies installed"
else
  die "npm install failed. Check your network/proxy, then re-run this script."
fi

step "Installing headless Chromium for PDF/PPTX export"
if ( cd "$TEMPLATE_DIR" && npx --no-install playwright install chromium >/dev/null 2>&1 ); then
  ok "Chromium ready"
else
  warn "Could not pre-install Chromium. Exports will attempt to fetch it on first use."
  warn "You can retry manually: cd <deck-dir> && npx playwright install chromium"
fi

# ------------------------------------------------------------------- verify ----

if [ "$SKIP_VERIFY" -eq 0 ]; then
  step "Verifying the toolchain with a real export"
  if ( cd "$TEMPLATE_DIR" && npx --no-install slidev export --format png --output dist/_verify slides.md >/dev/null 2>&1 ); then
    VERIFY_COUNT=$(find "$TEMPLATE_DIR/dist/_verify" -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
    rm -rf "$TEMPLATE_DIR/dist"
    ok "Rendered $VERIFY_COUNT slides successfully"
  else
    warn "Smoke test failed. The skill is installed, but check exports manually:"
    warn "  cd $TEMPLATE_DIR && npx slidev export --format png --output dist/test slides.md"
  fi
fi

# ------------------------------------------------------------------ cleanup ----

if [ "$KEEP_WARM" -eq 0 ]; then
  step "Trimming the template"
  rm -rf "$TEMPLATE_DIR/node_modules"
  info "Removed template node_modules. New decks install from the local npm cache,"
  info "which keeps this working offline. Pass --keep-warm to skip this next time."
else
  info "Keeping template node_modules (--keep-warm)"
fi

# ------------------------------------------------------------------- linking ----

LINKED_DIR=""
if [ "$SCOPE" = "global" ] && [ -n "$LEGACY_SKILL_ROOT" ] && [ -d "$(dirname "$LEGACY_SKILL_ROOT")" ]; then
  step "Linking into the IDE-extension skills directory"
  mkdir -p "$LEGACY_SKILL_ROOT"
  LEGACY_LINK="$LEGACY_SKILL_ROOT/$SKILL_NAME"
  if [ -e "$LEGACY_LINK" ] || [ -L "$LEGACY_LINK" ]; then
    warn "Already exists, leaving alone: $LEGACY_LINK"
  elif ln -s "$SKILL_DIR" "$LEGACY_LINK" 2>/dev/null; then
    LINKED_DIR="$LEGACY_LINK"
    ok "Linked $LEGACY_LINK"
  else
    warn "Could not symlink; copy manually if you use the IDE extension:"
    warn "  cp -R \"$SKILL_DIR\" \"$LEGACY_LINK\""
  fi
fi

# --------------------------------------------------------------------- done ----

SIZE="$(du -sh "$SKILL_DIR" 2>/dev/null | cut -f1 || echo '?')"

printf '\n'
ok "Done. Skill installed ($SIZE)"
printf '\n'
printf '  %sLocation%s   %s\n' "$BOLD" "$RESET" "$SKILL_DIR"
printf '  %sScope%s      %s\n' "$BOLD" "$RESET" "$SCOPE"
[ -n "$LINKED_DIR" ] && printf '  %sAlso at%s    %s %s(symlink)%s\n' "$BOLD" "$RESET" "$LINKED_DIR" "$DIM" "$RESET"
printf '\n'
printf '  %sNext steps%s\n' "$BOLD" "$RESET"
printf '   1. Restart your Antigravity session so it re-detects skills.\n'
printf '   2. Ask your agent something like:\n'
printf '        %s"Build me a 10-slide deck on <topic> using the slidev-deck skill"%s\n' "$DIM" "$RESET"
printf '   3. It should scaffold, render slides to PNG, look at them, and iterate.\n'
printf '\n'
printf '  %sManual use%s\n' "$BOLD" "$RESET"
printf '   %s/scripts/new-deck.sh ~/decks/my-talk "My Talk"\n' "$SKILL_DIR"
printf '   cd ~/decks/my-talk && npm run dev\n'
printf '\n'
