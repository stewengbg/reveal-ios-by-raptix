# Role-based mobile experience

The iOS app should look completely different depending on who opens it. A regional owner doesn't want to see "Check in" buttons. A store associate doesn't care about fleet KPIs. Three target roles, three home screens.

## The three roles

| Role | Swedish | Who | What they care about | Web access |
|---|---|---|---|---|
| **Owner** | Ägare / regionchef | Tenant owner, admins, multi-site oversight | Fleet performance, exceptions, where to send help | Yes |
| **Manager** | Butikschef | One site, accountable for that site's numbers | Today's performance, staff coverage, sensor health, immediate problems | Yes |
| **Associate** | Butiksbiträde | Shop floor staff | Check in / out, what to do right now, queues forming | **Mobile only** |

A user can have more than one role. Stefan-as-owner might also be the manager of one specific site. The app needs a role/site switcher in the profile menu — but defaults to the most-privileged role on first launch.

---

## Owner — fleet view (`OwnerHomeView`)

The web app's multi-site overview translated to mobile. Already in scope from the existing scaffold.

**Top of screen — fleet pulse**
- Live people across all sites (sum)
- Visitors today, with % delta vs typical
- "Busiest right now" — named site
- Healthy sites (3/4)

**Needs-attention strip** (only when something's wrong)
- Pinned at top, red accent
- Lists sites with queue alerts or offline sensors
- Tap → drills into that site's manager view

**Site card grid**
- One card per site: name, busy pill (Quiet / Steady / Busy), live people, queue badge, sensor health dot
- Tap → drills into manager view for that site

**Insight footer**
- Today vs typical
- Sensor health summary
- Push notification: "ICA Östermalm has had a queue ≥ 5 for 8 minutes"

---

## Manager — single-site view (`ManagerHomeView`)

The single-site Overview from the web, mobile-first. This is the screen most managers will live in.

**Hero strip**
- People in store now (big number)
- Visitors today + vs-typical delta
- Busy pill + narrative ("Today is busier than typical")

**Queue card**
- Live: "3 people at checkout"
- Banner if ≥ 5: "Consider opening another lane"
- Tap → checkout sensor detail

**Staff on shift** *(new — depends on check-in)*
- Avatar list of who's checked in right now
- "2 on the floor · 1 at checkout" (associates tag their role on check-in)
- Coverage warning if traffic spikes while shift is thin

**Sensor health**
- Temperature, humidity, water sensor status
- Red dot if any out of compliance with role policy

**Today's standout moments**
- Busiest hour so far
- Quietest hour
- Expected peak ahead

**Hourly footfall chart**
- Today vs typical-day overlay
- Same data as web's `TodayHourlyChart`

---

## Associate — task view (`AssociateHomeView`)

This is the new screen — nothing like it exists in the web app. Built for someone standing on the shop floor, glancing at their phone for 5 seconds.

**Check in / out — the headline action**
- One big primary button at the top
- States: "Check in" → "Check out" once on shift
- On check in: pick role tag (Floor / Checkout / Back office) + confirm site (auto-detected via geofence if we add it later)
- On check out: optional "Notes" field for handover

**Queue status — live, glanceable**
- Big tile, colour-coded: green (calm) / yellow (steady) / red (queue forming)
- Headline number: "3 people at checkout"
- Subtext: "Opened 4 min ago" or "Down from 6"

**On shift with me**
- Avatar row of other checked-in staff
- Each shows their role tag (Floor / Checkout / Back office)
- Useful for "where is X?" without messaging

**Customers right now**
- Calm number: "12 in store"
- Subtle, not the headline
- For context, so the associate knows whether to expect activity

**Optional add-ons (later)**
- Cars in car park (for "is the parking full?" questions)
- Notes/handover board between shifts

### Auto check-out at store close

A forgotten check-out poisons "who's on shift now" and inflates labour stats. Solved server-side, no tracking, no permissions.

- Each site already has `store_hours` per weekday (we use them to mask the heatmap).
- A new `auto-close-shifts` cron runs every 5 minutes. For each site, if today's closing time has passed, close any open shifts:
  - `checked_out_at = closing_time` (not cron-fire time — keeps labour stats clean)
  - `auto_closed_reason = 'store_closed'`
- Works even if the phone is dead, in airplane mode, or the app is killed — nothing client-side needed.
- Optional gentle push to the user once the close happens: *"You were checked out at 21:00."* Off by default; managers can enable per site.

We deliberately do **not** geofence-track associates. An app that knows when an employee leaves the building reads as surveillance no matter how the privacy copy is written — and in Sweden it would also need IMY justification and likely MBL negotiation with Handels. The cron solves 90 % of forgotten checkouts; the rest are caught manually by the manager.

### Queue alert — the live coordination loop

This is what makes the app worth keeping installed. The flow:

1. **Trigger.** `checkout_now` crosses the site's threshold (e.g. ≥ 5) and stays there for N seconds (debounce, so a 3-second spike doesn't fire). A `queue_alerts` row opens.
2. **Push fan-out.** Every associate currently checked in at that site gets a push: *"Queue forming at checkout — 6 customers waiting"*. The manager gets it too as a fallback.
3. **In-app banner.** Anyone with the app open sees the queue tile flip red, with a primary action: **"I've got it"**.
4. **Acknowledgment.** First tap wins. That user's name + role is stamped on the alert. The tile changes to **"Anna is opening a lane"** with a tick.
5. **Push to the rest of the team.** All other checked-in associates (plus manager) get a follow-up push: *"Anna has taken the queue."* No need to drop what they're doing.
6. **Auto-resolve.** When `checkout_now` drops back below threshold, the alert closes silently. No "all clear" push (avoids notification fatigue) — but the manager view shows the closed event in the day's timeline.
7. **Escalation.** If nobody acks within 2 minutes (configurable), a second push fires marked *"Still no one"* — manager + everyone again. After 5 minutes, escalate to the owner.

**Edge cases worth deciding upfront:**
- **Can multiple people ack?** No. First-wins. Others see "Anna's got it" — opening duplicate lanes is wasted effort.
- **Can you un-ack?** Yes, with a "Actually, can someone else?" button — reopens the alert and fans out again. Same alert ID, new ack round.
- **Queue stays high after ack?** Soft re-prompt to the acker only after 3 minutes: *"Still 6 in queue — need backup?"* Doesn't reopen to the team unless they say yes.
- **Off-shift staff?** Don't get pushed. Only checked-in users on the relevant site.
- **Manager opening the lane themselves?** Same flow — they can ack too.

What it deliberately does NOT show:
- Visitors today / yesterday — not their job
- Sensor compliance — manager problem
- Other sites — not their site
- KPI configuration / settings

---

## Web access gating — associates are mobile-only

The shop-floor experience is built for a phone in someone's apron pocket, not a desktop. A check-in toggle and a queue tile make no sense on a 1440-px monitor in the back office. Plus, opening the web to associates means giving every part-time worker a `reveal.raptix.se` login — a support and onboarding tax we don't want to carry.

So: **associates can sign in to the iOS app and nothing else.**

### How we enforce it

Supabase itself can't natively distinguish "this token came from the web vs the mobile app" — both hit the same `/auth/v1/token` endpoint with the same anon key. The clean answer is to gate at the **app level**, using the role the user has, not the auth provider.

**In the web app** (existing React codebase, no backend changes):

1. After `signInWithPassword` resolves, the app already calls the scope resolver to fetch `tenant_memberships`, `platform_user_roles`, and (once we ship them) `site_memberships`.
2. Add a derived flag: `webAccessAllowed = hasAny(tenantMembership, platformRole, siteMembership.role IN ('manager'))`. An associate-only user has none of these → `false`.
3. If false: immediately sign the session out (`supabase.auth.signOut()`) and render a small "Mobile only" screen with an App Store link and a one-liner: *"This account uses the Reveal mobile app. Download it here."*
4. The session was issued for a fraction of a second, then discarded. The user never sees the dashboard.

**In the iOS app:** no special gating needed. iOS happily accepts associates (and managers and owners). The mobile is the broad door; the web is the gated one.

### Why not a server-side block?

A Supabase Auth Hook (Pre-Sign-In) could theoretically refuse the sign-in. But the hook can't tell which client is asking — meaning we'd either refuse the role everywhere (breaks iOS too) or have to thread a custom header through that hooks don't see. The app-level check is simpler, works today, and is just as effective for "wrong app" cases. We're not defending against a malicious associate who decrypts their own token to call the REST API directly — RLS already handles that.

### Edge cases

- **Multi-role users** (associate at one site, manager at another): they have a manager `site_membership` → `webAccessAllowed = true`. Web works. iOS asks them on first launch which role to default to.
- **Invite flow**: the existing invite flow lands the user on the web to set a password. Once the password is set, we run the same `webAccessAllowed` check. If false, show *"Password set. Now open the Reveal iOS app."* with an App Store / TestFlight link. Don't block the password-set step itself — the user needs that to work everywhere.
- **Password reset** (associate forgets password): same as above. The reset email link goes to the web; the web lets them set a new password and then redirects them to the "open the mobile app" screen.
- **Promotion or demotion**: a manager who becomes an associate-only later (rare, but possible) starts being blocked from web on next login. No migration needed; the check is dynamic.

### Schema implication

This is the second reason `site_memberships` is the right level for storing manager/associate (the first being site-scoped RLS). It also means `tenant_memberships` stays the canonical place for owner/admin — `webAccessAllowed` falls naturally out of the existing data once `site_memberships` lands.

---

## How the app picks the right view

Two-step detection on app launch:

1. **What memberships does this user have?**
   - `tenant_memberships.role IN ('owner','admin')` → owner role available
   - `site_memberships.role = 'manager'` for site X → manager role for X available
   - `site_memberships.role = 'associate'` for site Y → associate role for Y available

2. **Pick the default**
   - Most-privileged role wins on first launch
   - User can switch via profile menu ("View as Manager for ICA Östermalm")
   - Last choice is remembered in `UserDefaults`

If the user only has one role at one site, no switcher is shown.

---

## Backend changes needed

The existing `tenant_memberships` table handles owners. **Managers and associates need new data.**

### New table: `site_memberships`

```sql
create table site_memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  site_id uuid not null references sites(id) on delete cascade,
  role text not null check (role in ('manager','associate')),
  created_at timestamptz not null default now(),
  unique (user_id, site_id, role)
);
```

RLS: a user reads their own memberships; tenant owners/admins read all memberships within their tenant; managers read memberships for their site.

### New table: `staff_shifts`

```sql
create table staff_shifts (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references sites(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_tag text not null check (role_tag in ('floor','checkout','back_office')),
  checked_in_at timestamptz not null default now(),
  checked_out_at timestamptz,
  auto_closed_reason text check (auto_closed_reason in ('store_closed','manual')),
  notes text
);

create index on staff_shifts (site_id, checked_in_at desc) where checked_out_at is null;
```

A row with `checked_out_at` null = currently on shift. `auto_closed_reason` records whether the close was manual or store-hours-driven (useful for labour stats — manual closes are "real" worked time, store-close closes are an estimate).

### New table: `queue_alerts`

```sql
create table queue_alerts (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references sites(id) on delete cascade,
  started_at timestamptz not null default now(),
  threshold int not null,
  triggered_value int not null,
  acknowledged_by uuid references auth.users(id),
  acknowledged_at timestamptz,
  resolved_at timestamptz,
  escalation_count int not null default 0
);

create index on queue_alerts (site_id, resolved_at) where resolved_at is null;
```

One open alert per site at a time. Re-trigger only after the previous one resolves.

### Edge functions

- `check-in` — opens a `staff_shifts` row, validates the caller is a member of the site
- `check-out` — closes the user's open shift; accepts optional `reason` to record `auto_closed_reason`
- `staff-on-shift` — returns active shifts for a site (used by Manager + Associate views)
- `auto-close-shifts` — cron every 5 min; closes shifts at sites where today's `store_hours` closing time has passed
- `evaluate-queue-alerts` — runs alongside `scheduled-sync`; opens alerts when threshold crossed and the previous alert is resolved; closes alerts when value drops back below; fans out APNs pushes via Apple's HTTP/2 endpoint
- `acknowledge-queue-alert` — takes alert_id + caller user_id, stamps ack, triggers fan-out push to the rest of the on-shift team

The fetch-latest-counts / sensor pipelines stay as they are.

### Push infrastructure

- Apple Developer Program account (Stefan likely has one) + APNs auth key (.p8)
- New table `device_tokens(user_id, token, platform, last_seen_at)` — app registers on launch
- Edge function `send-push` wraps APNs HTTP/2 calls so other functions just call it with a list of user IDs and a payload
- Use Apple's "alert" push type with `mutable-content` so the badge count + sound work even on locked screen

---

## Open product calls (need Stefan's input)

1. **Geofence-based auto check-in?** Tap "Check in" when you arrive, app uses Core Location to confirm you're at the site. Phase 2 — adds friction-free check-in but needs location permission + privacy copy.
2. **What's the queue threshold per role?** Manager sees ≥ 5 as red; should associates see ≥ 3 as yellow? Or do we let managers configure per-site?
3. **Multi-site managers** — can a manager be tied to more than one site? Likely yes (small chains, one manager covering 2 stores). Schema supports it; UX needs a site picker in the manager view.
4. **Associates: can they switch sites?** A floating associate who works at 3 different ICA stores — do they pick which one each shift? Probably yes.
5. **Push notifications — who gets what?**
   - Owner: cross-site exceptions, daily summary, escalations (no ack after 5 min)
   - Manager: queue alerts for their site (parallel to associates, as fallback), sensor out-of-range
   - Associate: queue alerts if checked in at that site, plus ack-fan-out ("Anna has taken it")
6. **Escalation timing** — 2 min to first re-prompt, 5 min to owner. Reasonable defaults or per-site override?
7. **Auto-resolve push?** Plan says silent close. Do managers want a wrap-up push ("Queue resolved after 4 min, peak was 8")?
8. **Store-close auto-checkout push** — silent (just close), or send the *"You were checked out at 21:00"* notification? Lean silent — but ask managers what their staff prefer.
6. **App icon + brand** — currently placeholder. Need final Raptix red and an icon before TestFlight.

---

## Suggested build order

Phase order is about getting feedback fastest. Each phase is a TestFlight build.

| Phase | Scope | Value |
|---|---|---|
| **1. Owner view** | Port multi-site overview to native. Reuse existing tenant data, no schema change. | Stefan-shaped, demos easily. Already half-built in the scaffold. |
| **2. Manager view** | Single-site overview with all the existing data. Still no schema change. | A store manager can replace their daily-look-at-the-web-dashboard habit. |
| **3. Role detection + switcher** | Default to most-privileged role, profile-menu switcher. | Both roles co-exist for one user. |
| **4. `site_memberships` + assignment UI** | Backend table + simple admin UI (in web app) for tenant owners to assign managers and associates to sites. Web app gains the "associates are mobile-only" gate on the login flow. | Unlocks per-role gating. |
| **5. `staff_shifts` + Associate view** | Check-in/out, live queue tile, on-shift roster. Store-close auto-checkout cron lands with this — server-only, no app work. | The differentiating feature. Worth getting right. |
| **6. Push infrastructure** | APNs setup, `device_tokens` table, `send-push` edge function. | Foundation for everything in phase 7. |
| **7. Queue alert loop** | `queue_alerts` table, evaluate + ack edge functions, fan-out, escalation. | The team-coordination feature. The reason the app stays installed. |
| **8. Other pushes** | Sensor offline, daily summaries, owner escalation. | Round out the notification surface. |

---

## What to decide before coding

- Are these three roles the right cut? (vs e.g. splitting "owner" into vendor-admin vs tenant-owner)
- Is the check-in feature in scope for v1, or save for v2?
- Should managers be able to configure their own queue thresholds, or does the owner set them centrally?
