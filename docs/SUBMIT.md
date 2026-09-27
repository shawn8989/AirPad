# Finish the submission — everything left, in order

Standalone. You need a Mac with Xcode, an iPhone, and a browser. Nothing here
needs Claude; work top to bottom and stop when Submit is grey.

Three other docs exist and this one does not repeat them:

| Doc | Use it for |
|---|---|
| `docs/FILL-IN.md` | the exact text for every App Store Connect field |
| `docs/QA.md` | the full manual test script |
| `docs/APPSTORE.md` | why each listing decision was made |

`docs/RELEASE.md` is the pre-1.0 setup playbook. Everything in its §0–§2 and §4
is already done; ignore it.

---

## Where things actually stand

Done: both repos on `main` and CI-green; Wield Host **1.0.1** signed, notarized,
stapled and published (`releases/latest` → `v1.0.1`); GitHub Pages live with all
three URLs resolving; app record created (Apple ID 6804338937,
`com.SOTechy.AirPad`); IAP `com.airpad.pro.lifetime` created; Paid Applications
Agreement signed; every field in `FILL-IN.md` validated against Apple's limits.

Not done: the six steps below. All six need hardware or a browser, which is why
they are still here.

---

## 1. Merge the pairing-denial fix (10 min)

Branch `claude/youthful-newton-fd8xct` in **both** repos carries one commit
each, fixing this: denying the pairing prompt on the Mac — or letting it time
out — made the phone reconnect and put the prompt straight back up, forever.

```
cd ~/Developer/AirPad        && git fetch origin && git checkout main && git merge --ff-only origin/claude/youthful-newton-fd8xct && git push origin main
cd ~/Developer/AirBridge-mac && git fetch origin && git checkout main && git merge --ff-only origin/claude/youthful-newton-fd8xct && git push origin main
```

If `--ff-only` refuses, `main` moved; use a plain `git merge` instead.

**The Mac half does not need a new Wield Host release.** The phone infers a
refusal from the generic `error` that 1.0.1 already sends, precisely so 1.0.1
stays good enough. The Host's new explicit `pair_denied` rides along in the next
Host build, whenever that happens. Don't re-notarize for this.

Verify after merging: deny the prompt on the Mac once. The phone should say
"The Mac declined this device" and go quiet. Nothing should reappear on the Mac.

## 2. Screenshots (30 min)

Only one is uploaded (`docs/screenshots/framed/01-trackpad-*.png`), and one is
Apple's minimum, so this is not a blocker — but one screenshot sells badly.

The workflow (`.github/workflows/screenshots.yml`, run it from the Actions tab)
captures on a CI Simulator and frames to exactly 1284×2778 and 1320×2868. It
cannot capture Hand Mouse or Gesture Studio: the Simulator has no camera.

Fastest honest path: take the camera ones by hand on the device
(volume-up + side button), drop them in a folder, and run them through the same
framer — it takes an input *directory* and an output directory, and emits both
required sizes for every PNG it finds:

```
python3 scripts/frame-screenshots.py ~/Desktop/raw-shots docs/screenshots/framed
```

Captions come from the filename: the stem is looked up in `CAPTIONS` inside
`scripts/frame-screenshots.py`, so name a file after an existing key (or add a
key) to get a caption instead of a bare frame.

Shot order that reads best on the product page: trackpad → Live Screen on a real
desktop → Hand Mouse with the pose badge → Desktops & Apps → Gesture Studio →
Media. Keep personal data off the Mac's screen in every capture.

Screenshots can be swapped any time while the version sits in Prepare for
Submission, including after you've filled everything else in.

## 3. Sandbox-test the purchase (20 min)

1. iOS **Settings → Developer → Sandbox Apple Account**: sign in with a sandbox
   tester (App Store Connect → Users and Access → Sandbox Testers).
2. Run a **Debug** build on the device. In *Wield's own* Settings → Developer,
   turn **Simulate Free** on — a Debug build is unconditionally Pro otherwise,
   and the lock badges never appear.
3. Open the paywall (the trial banner, or any Pro row in Modes) and buy. The
   price must come from StoreKit; if it reads "Loading price…" forever the IAP
   isn't ready in App Store Connect — that's an ASC problem, not a code one.
4. Delete the app, reinstall, tap **Restore Purchase**. Pro must come back.

You do not have to turn Simulate Free off before archiving: the whole toggle and
the always-Pro shortcut are inside `#if DEBUG`, so a Release build cannot carry
either. (`docs/APPSTORE.md` §0 says otherwise — it's wrong, harmlessly.)

## 4. Test on hardware — the wedging tests are the ones that matter (45 min)

Run `docs/QA.md` end to end. Do not skip the four wedging cases in
`FILL-IN.md` § "The wedging tests": these releases changed input injection, and
a missed key-up latches your *physical* keyboard and mouse until you reboot.
Quitting Wield Host releases everything it holds, so that's the escape hatch.

## 5. Fill in App Store Connect (30 min)

Work straight down `docs/FILL-IN.md` — version page, then In-App Purchases,
then App Information, then App Privacy. Two things there are easy to miss:

- The IAP must be **attached to version 1.0** (version page → In-App Purchases
  → **+**). A first non-consumable ships with a version; unattached, the build
  goes up without anything to buy.
- App Store Version Release → **Manually release this version**, so approval
  doesn't publish you at 3am.

## 6. Archive, upload, submit (30 min + processing)

1. Xcode → target Wield → set **Build** to one higher than your last upload.
2. Any iOS Device → Product → **Archive** → Distribute → App Store Connect →
   Upload. Export compliance answers itself:
   `ITSAppUsesNonExemptEncryption` is already `false`.
3. Wait for processing (10–40 min), then select the build on the version page.
4. Attach a 30–60s demo video as an App Review attachment — connect → trackpad
   → Live Screen → hand gestures. A reviewer without a Mac cannot exercise a
   single feature, and this is the top review risk on the whole submission.
5. **Add for Review** → **Submit**.

---

## Before you press Submit

- [ ] Pairing-denial fix merged and denial verified on hardware (§1)
- [ ] Wedging tests passed (§4)
- [ ] Sandbox purchase *and* Restore both work (§3)
- [ ] All three URLs load in a browser
- [ ] Build selected on the version page
- [ ] IAP attached to version 1.0
- [ ] Demo video attached to App Review Information

## If it comes back rejected

Most likely reason, by a distance: **the reviewer could not test it**, because
they didn't install Wield Host or didn't grant Accessibility. The reply is the
demo video plus the numbered steps already in the reviewer notes — resubmit with
a Reply in Resolution Center rather than a new build, since nothing in the app
is wrong.

Second most likely: the IAP is rejected separately from the app. Its own review
screenshot must show the paywall, and its review notes must say the 7-day trial
makes every Pro feature testable without buying.

Anything that needs a code change goes on `main` as its own commit — CI is green
there and the branch used for 1.0 work is now merged.
