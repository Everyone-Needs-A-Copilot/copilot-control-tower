# The Control Tower Site (deployable landing and resource site)

Design source-of-truth for the small, org-internal, org-branded website that ships
**with** Copilot Control Tower as a deployable artifact. A company hosts it on its own
web space, points its invitation email at it, and a curious employee lands here to
**learn before installing**, download the app, and come back later to watch how each
piece works.

This is a design document. Nothing is built here. It extends the two surfaces already
mocked in `docs/09-prototypes/user-experience-walkthrough.html` (screen 1.1 the
invitation email, screen 1.2 the download page) from a bare download into a small
resource site, per the owner brief of 2026-07-16.

**Grounding read:** `SOUL.md` §7 (voice), `docs/03-design/control-tower-copy-deck.md`
(hard rules: no em-dashes, plain language, action-named buttons, never fake-healthy),
`docs/03-design/brand-assets.md` (the Control Tower logo is the site's mark; the
aviator glyph is menu-bar only, never here).

Binding constraints this design inherits (all owner-ratified):

- **Two builds.** The public user build is downloadable here. The admin build reaches
  admins only through a private channel from the publisher, and is **never** linked or
  downloadable from this public site.
- **Videos link out to YouTube**, and every URL is org-swappable. No player is embedded,
  no video is hosted here.
- **The site ships as a static artifact.** No server, no tracking, no external calls
  beyond the YouTube links the org chose.
- **The Control Tower logo is the site's mark.** Full color, never tinted. The aviator
  glyph does not appear on this site.

---

## 1. Purpose and audiences

The site exists to turn "you're getting this thing" into "I understand what I'm getting,
and here's how to get it," without a single person having to be technical. It is a
utility site for one company's own people, not a marketing site for the world.

**Jobs to be done, one per audience:**

- **The curious employee (from the invitation email).** When I get an email saying my
  company is setting up AI copilots on my Mac, I want to look before I click anything, so
  I can trust this is real and understand what it does. This is the owner's "you're
  curious? Learn more" landing. It is the emotional job the site is built around: dissolve
  the arriving employee's uncertainty before asking them to download anything.
- **The user (Bob, ready to install).** When I've decided to go ahead, I want the right
  download and a plain how-to, so I can install it and see what each copilot is for. This
  is the existing download page, plus the short videos.
- **The admin (Earl).** When I'm the person standing this up for my organization, I want
  to be pointed at my own materials and the private admin build, so I can set up the org
  without hunting. The site tells the admin where to go. It carries **zero** admin
  secrets, no admin download, no org configuration.
- **The publisher (the open-source contributor).** When I want the source, I want a clear
  pointer to the open-source project, so I can read, fork, or contribute. The site links
  out to the public repository; it is not itself the project's documentation home.

One site. Org-internal. Org-branded. Small on purpose.

---

## 2. Information architecture and sitemap

A five-entry site. Home is the download page already designed in the walkthrough; the
rest are thin resource pages around it. Nav stays within Miller's limit with room to
spare, so nothing needs a hamburger and nothing hides.

```
Copilot Control Tower  (org-branded header, Control Tower logo)
├── Home / Download          ← screen 1.2, the download page (the default landing)
├── What you get             ← the four copilots, in plain language + per-copilot videos
├── Watch how it works       ← the video library (one page, every how-to video)
├── For admins               ← points admins to their materials + the private admin build
└── Who to ask               ← renders the org's AdminContact (the named human)
```

**Nav rules:**

- Persistent top nav on every page. Desktop shows all five inline (no hamburger). Narrow
  screens collapse to a single stacked menu, never an icon-only mystery.
- Current page is marked by weight and an underline, not color alone.
- The Control Tower logo in the header links Home.
- Nothing in the nav ever reveals the admin build. "For admins" is orientation, not a
  download.

**Why this set and not more:** a marketing site would add pricing, testimonials, a blog.
None of that serves any of the four jobs. Every page here answers one question a real
person in the company will actually ask: *what is this, how do I get it, how does it
work, I'm the admin where do I go, who do I ask.*

---

## 3. Page-by-page content outline

Voice throughout: calm, plain, no hype, no em-dashes, buttons named for what they do.
Copy below is suggested and ready to drop in; the org swaps its name and links.

### 3.1 Home / Download

Home **is** the download page from walkthrough screen 1.2, unchanged in its core, with a
short welcome-tour video added below the install steps and a quiet nav added above. It
opens with the end in view so the arriving employee sees the whole shape before
committing.

- Mark: Control Tower logo, full color, centered.
- Title: `Copilot Control Tower`
- Subtitle (kept from 1.2): `Installs your team's copilots on your Mac and keeps them
  current. No terminal.`
- Primary action: **`Download for Mac`** (serves the org's user-build `.dmg`).
- Quiet line under the button: `For macOS. Signed by <Org>. About 20 MB.`
- Three steps (kept from 1.2):
  1. `Download the app.`
  2. `Open it and drag it to your Applications.`
  3. `Open it once. It'll walk you through the rest.`
- **Welcome tour video slot** (`welcomeTour`): a low-emphasis link, not an autoplay.
  Label: `Watch a short welcome tour` with the YouTube out-link chip. This is the same
  welcome video the in-app wizard offers on its first screen (§6).
- Footer (kept from 1.2): `Set up by your IT team. Questions? Reply to the email that
  sent you here.` plus a quiet link to **Who to ask**.

**Empty state (welcome video not yet provided):** the slot renders a calm placeholder,
`A welcome tour will be added here.` Never a broken embed, never a dead play button.

### 3.2 What you get

The "learn before installing" page the owner's email link is really promising. Plain
descriptions of the four copilots, each with its own short explainer video (the same
"What's this?" videos the wizard links out to on its Confirm step).

- Title: `What you get`
- Intro: `Your company is setting up four copilots on your Mac. Control Tower is how they
  land and stay current. Here's what each one is for, in plain language.`
- Four calm rows, each a name, one plain sentence, and its explainer video link:
  - `Claude Copilot`: `Your day-to-day AI partner for writing, thinking, and getting
    work done.` + video link (`claudeCopilot`).
  - `Codex Copilot`: `The AI coding tool, for the people who build software.` + video
    link (`codexCopilot`).
  - `Knowledge Copilot`: `Your company's knowledge, ready to ask.` + video link
    (`knowledgeCopilot`).
  - `CLI Copilot`: `The quiet engine that keeps everything running.` + video link
    (`cliCopilot`).
- Honest closing line: `You don't choose between these. Everyone on the team gets what
  the team set up. Control Tower keeps it current on its own.`
- Secondary action at the foot: `Download for Mac` (returns the reader to the action once
  they understand what they're getting).

**Empty state (an explainer video not provided):** that copilot's row keeps its name and
sentence; the video link is replaced by the quiet line `A short video will be added
here.` The description alone still teaches.

### 3.3 Watch how it works

One video library page, so every how-to lives in a single place a returning user can find
again. It reads the same video registry as everything else (§4, §6); a slot with no URL
simply does not appear, so the page is never padded with dead tiles.

- Title: `Watch how it works`
- Intro: `Short videos on setting up and using Control Tower. Each one opens on YouTube.`
- Grouped, in this order:
  - **Getting started:** `Welcome tour` (`welcomeTour`).
  - **The copilots:** the four explainer videos from §3.2.
  - **For admins:** `Setting up your organization` (`adminStandup`), the admin standup
    overview. Present here as education only. It explains the admin path; it is not a
    download and links to nothing private.
- Each entry: a thumbnail-framed link with a play affordance, the video title, and the
  YouTube out-link chip. Shape and the chip carry the "this opens elsewhere" meaning, not
  color alone.

**Empty state (no videos provided yet):** the whole page shows one calm block:
`Videos will appear here once your organization adds them.` Explanation, no false
promise, no broken grid.

### 3.4 For admins

Orientation for the admin, and a hard boundary. It points the admin at their own
materials and the private admin build, and it holds nothing sensitive.

- Title: `For admins`
- Intro: `Setting this up for your organization? The admin build and its guide come to you
  privately, not from this page.`
- Plain guidance:
  - `The admin build is a separate app. You receive it through the private channel your
    publisher gave you, never as a public download.`
  - `It walks you through standing up your organization on GitHub, step by step. This app
    never changes anything on GitHub itself; it gets you ready and checks the result.`
  - Watch the overview: link to `Setting up your organization` (`adminStandup`).
- What is deliberately **not** here, stated plainly so no admin goes looking:
  `You won't find the admin build, any keys, or any organization settings on this page. By
  design.`
- Pointer to the source, for the publisher-minded admin: `Copilot Control Tower is open
  source.` + link to the public project (§7 open question on whether this links out or
  the site hosts more).

### 3.5 Who to ask

The human backstop. Renders the org's `AdminContact`, the named person from the invitation
email, so no one is ever routed into a support void. This is the site's version of the
in-app AdminContact card (walkthrough screen 25).

- Title: `Who to ask`
- Intro: `If anything looks off, or you're just not sure, reach a real person.`
- Contact card (rendered from `adminContact`): the name, the role, and the email as a
  `mailto:` link. Example: `Earl Mota, IT` / `earl@acme.com`.
- Reassurance line: `This is the person who set Control Tower up for your company. Replying
  to the email that sent you here reaches them too.`

**Empty / misconfigured state (no AdminContact set):** never show a blank card or a broken
`mailto:`. Fall back to `Reply to the email that invited you. It reaches the person who set
this up.` Flag in the config docs that shipping without an AdminContact is a
misconfiguration, since SOUL routes org trust through a named human.

---

## 4. Customization model: swap values, not code

An org "spins it up" by editing **one** config file and dropping in two assets (its logo
and its signed `.dmg`). Everything else works untouched. The principle, stated once:
**swap values, not code.**

Suggested shape of the single org config (illustrative; the exact format is an
implementation choice, but the surface is this small):

```
org:
  name: "Acme"                         # appears in the header, titles, "Signed by"
  logo: "assets/org-logo.svg"          # the org's own mark, if it wants one, beside/above the Control Tower logo
adminContact:
  name: "Earl Mota"
  role: "IT"
  email: "earl@acme.com"
download:
  artifact: "downloads/CopilotControlTower.dmg"   # the signed user build the org hosts beside the page
  size: "About 20 MB"
videos:                                # the video registry (one list, two consumers: this site + the in-app wizard, §6)
  welcomeTour:       "https://youtu.be/..."
  claudeCopilot:     "https://youtu.be/..."
  codexCopilot:      "https://youtu.be/..."
  knowledgeCopilot:  "https://youtu.be/..."
  cliCopilot:        "https://youtu.be/..."
  adminStandup:      "https://youtu.be/..."
support:
  publicRepo: "https://github.com/.../copilot-control-tower"
```

Rules that keep this safe and simple:

- **Values only.** An org changes its name, logo, contact, download path, video URLs, and
  support links. It never edits page structure, copy logic, or styling to get a working
  site.
- **Missing values degrade to honest empty states** (§3), never to broken embeds, dead
  links, or blank cards. A video URL left blank hides that slot; it does not break a page.
- **The org's own logo is optional and additive.** The Control Tower logo remains the
  product mark; an org logo, if provided, sits alongside it. The aviator glyph is never a
  site option.
- **No secret ever belongs in this config.** The only "address" here is a public YouTube
  URL, a public repo URL, and an internal `mailto:`. If a field ever looks like a secret,
  it is in the wrong file (the same rule the admin app enforces on its store address).

---

## 5. Deployment story (documentation level)

The site is a **static artifact** that ships inside the open-source product. A company
takes it, edits the one config, and hosts it on its own internal web space or intranet.
The signed user-build `.dmg` sits **beside** the page at the `download.artifact` path.

- **No server.** Plain static files. Any static host or intranet share serves it.
- **No tracking.** No analytics, no cookies, no beacons, no fingerprinting. An arriving
  employee is never measured.
- **No external calls** beyond the YouTube links the org chose. The page itself phones no
  home. Videos open on YouTube in a new tab when a person clicks; nothing loads until then.
- **The `.dmg` is the org's own signed build**, hosted at an org-controlled URL (matching
  walkthrough AS-2), not an outside host and not an App Store link.

**What does NOT live here, ever** (state it loudly so no future contributor adds it):

- The **admin build**. It is distributed privately from the publisher. There is no admin
  download, no admin link, no "request access" form on this public site.
- Any **secret**. No keys, no tokens, no store addresses, no org GitHub configuration. The
  config file holds only public URLs and an internal contact.
- Any **telemetry**. The site observes nothing and reports nothing. Silence is the whole
  posture, consistent with the product's own "quiet instrument" character.

---

## 6. Relationship map: how the site connects to everything else

```
Invitation email (org-sent, by AdminContact)
   │  "Curious? Learn more →"  ......... lands on ──► Home / Download
   │  "Download for Mac"                                  │
   └──────────────────────────────────────────────►  serves the USER build .dmg
                                                          │
                          the site and the in-app wizard  │
                          read the SAME video registry  ◄─┘
                                   │
   In-app wizard video links  ◄────┴────►  Site video slots
        (welcome, per-copilot "What's this?", admin standup)
```

- **The email's "Learn more" link lands on Home.** The owner's stated flow: an employee is
  curious, clicks the link, and arrives at their company's internal Control Tower site,
  which explains things. The same link (or the download button) also resolves to the
  download, so a decided employee is one click from the app and a curious one is one click
  from understanding.
- **The download button serves the user build.** Never the admin build. The admin build
  has no path from any surface a normal employee touches.
- **One video registry, two consumers.** The site's `videos` config and the in-app
  wizard's video links resolve from the same org-owned list. Swap a video URL once and both
  the site and the wizard point at the new video. This is the owner's "if they want to
  change videos out for their own videos, they should have that ability," made structural:
  there is one place to change, not two that can drift.

---

## 7. Open questions for the owner

1. **Publisher docs: host or link out?** Should "For admins" and the footer link out to the
   public GitHub repo for anything publisher-facing, or should the site carry a small
   publisher/source page of its own? Recommendation: link out. The site stays a thin
   internal utility; the repo is the project's real documentation home.
2. **Is the admin standup video public enough for this site?** The `adminStandup` overview
   is education, not a secret, but it lives on a page every employee can reach. Confirm the
   overview reveals nothing an org would not want a general employee to see. If it might,
   move that video behind the private admin channel and drop it from "Watch how it works."
3. **AdminContact on a public-internal page.** Rendering a named person's email on an
   intranet page is fine inside a company, but confirm orgs are comfortable with that
   versus a shared alias (for example `it-help@acme.com`). The config supports either; the
   default copy assumes a named human because SOUL routes trust through one.
4. **One org logo or two marks side by side?** The design keeps the Control Tower logo as
   the product mark and treats an org logo as optional and additive. Confirm the header
   composition when both are present (Control Tower logo primary, org logo secondary), or
   whether some orgs want their mark to lead.
5. **Does "Watch how it works" duplicate the per-copilot videos on "What you get"?** The
   same explainer videos appear in both places by design (learn-in-context on What you get,
   find-again in the library). Confirm that repetition is wanted, or fold the copilots into
   one page.

---

*Design complete. This document is the source of truth for the deployable site's purpose,
pages, copy, customization, and boundaries. Ready for visual design (route to uids) once
the open questions above are answered; the copy here is drop-in and matches the product
voice and the existing walkthrough surfaces.*
