# Venture Local

Made by Brandon Foley and Drew Floyd

---

## Inspiration

Venture Local grew out of wanting **exploration to feel tangible**, not another anonymous list of pins, but a personal “ledger” of where you’ve actually been. We were inspired by **passport stamps**, **local discovery** (small businesses and neighborhoods over chains), and the idea that **friends could nudge each other toward places worth visiting** without turning the app into a global popularity contest.

By helping people discover **nearby parks**, **hidden gems**, and **independent local businesses**, our app makes **sustainability** part of everyday life. Instead of encouraging users to **travel farther** or default to **large chains**, we nudge them toward **experiences already close to home**. This can **reduce routine travel emissions** while supporting **local businesses and communities**, which often have a **smaller environmental footprint** than **large-scale chain logistics**.

Rather than framing sustainability as **a chore**, the app turns **local exploration** into a **game**. Through **badges**, **rewards**, and **discovery**, we make staying curious about **your own community** feel fun, natural, and worthwhile.

---

## What it does

- **Map-first exploration** with category-tuned POIs, voice-assisted discovery, and **road coverage** that builds a sense of “unlocking” the city.
- **Explorer’s Ledger (Journal)**: level and XP, **city completion** for non-chain “locals,” category progress, recent discoveries, and **unique road distance** (miles or km from profile settings) derived from distinct OSM segments.
- **Passport**: partner stamps and QR flows for curated local experiences.
- **Badges** with secret and themed unlocks.
- **Social**: **friend recommendations** (share a place from the map), **per-user dismissals** synced to Supabase, map-style **category pins** (Shop / Fun / Parks / Food / Gems), and a **friends-only** XP leaderboard.
- **Cloud backup** (Supabase): profile, visits, friendships, recommendations, and dismissals—with **RLS** so users only see what they should.

---

## How we built it

- **Stack**: SwiftUI, SwiftData, MapKit, CoreLocation (including background where appropriate), Supabase (Auth + Postgres + RLS).
- **Data & sync**: `CloudSyncService` binds to the signed-in session; recommendations and dismissals are first-class tables, not only local state.
- **Progress math**: levels are driven by a **piecewise-linear XP ladder**—each step from level \(n\) to \(n+1\) costs  
  \[
  \Delta XP(n) = b + g\,n,\quad b = 25,\; g = 10.
  \]  
  Cumulative XP to **reach** level \(L\) is  
  \[
  XP(L) = \sum_{n=0}^{L-1} (b + g\,n) = L b + g\frac{(L-1)L}{2}.
  \]  
  City completion for locals uses a simple **coverage ratio** \(0 \le c \le 1\), e.g.  
  \[
  c = \frac{\text{locals discovered}}{\text{locals in scope}},
  \]  
  with chains handled separately so exploration XP and “true local” completion stay honest.
- **Geo**: haversine / local tangent-plane helpers for snapping, distances, and **polyline length** for road stats.
- **UX polish**: vintage paper theme, category-colored glyphs aligned between **map pins** and **Social** rows, and deep links from favorites and recommendations back to the map.

---

## Challenges we ran into

- **Location truth vs battery**: balancing **background updates**, road snapping tolerance, and not hammering Overpass when the map isn’t focused.
- **RLS product semantics**: friends can see recommendations but **shouldn’t delete another user’s row**—so dismissals are modeled as **`(user_id, recommendation_id)`** rows instead of destructive deletes.
- **Schema drift**: older recommendation rows missing `category_raw` forced **client-side fallback** (e.g. `CachedPOI` by `osm_id`) so Social still shows the right **glyph and color** when the cache has the place.
- **Sheet / map edge cases**: keeping place presentation stable (e.g. sheet identity) when state updates quickly.
- **Hackathon time**: shipping end-to-end **auth + sync + social** while keeping the **on-device** experience smooth when offline or misconfigured.

---

## Accomplishments that we're proud of

- A **cohesive exploration loop**: map → discover / claim → journal progress → badges → optional social proof.
- **Friend recommendations** that are **actionable** (open on map) and **respect privacy** (friends-only, dismissals synced).
- **Consistent category language** across filters, pins, and Social (including map-matched **fill opacity** and per-type colors).
- **Honest “local” completion** separate from chains and traveler notes where it matters.

---

## What we learned

- **Supabase RLS** is powerful but you have to design policies for **every** real user story (including “hide this for *me* only”).
- **Small schema fields** (like `category_raw`) save a lot of **client inference pain** if you add them early—or plan **migrations and fallbacks** deliberately.
- **Map + SwiftData + cloud** is tractable if you keep a clear **source of truth** per concern (device vs server) and merge conflicts predictably (e.g. max XP on profile pull).
- UX details—**pin grammar**, typography, and success states—matter as much as features for a “delightful” exploration app.

---

## What's next for Venture Local

- Richer **recommendation context** (short note, photo thumbnail) and optional **push** or in-app events when friends share.
- **Smarter category** rules and POI metadata (hours, accessibility, price hints) where licensing allows.
- **Seasonal / city-specific** badge campaigns and partner tooling.
- Deeper **privacy controls** (who can see home city, opt-out of leaderboard).
- Optional **Android / web** companion using the same Supabase schema for true cross-platform crews.

---

*Math uses LaTeX-style `\( … \)` and `\[ … \]`; render with MathJax/KaTeX or a preview that supports them.*

## Repo layout

- **`Venture Local/`** — Xcode project and iOS app source.
- **`Venture Local/Venture Local/Resources/SupabaseSchema.sql`** — SQL to run in the Supabase dashboard for tables, RLS, and grants.
