# Spade for iPhone

The native app: Swift, SwiftUI for the screens, SceneKit for the 3D scene.
It needs iOS 17 or newer and runs upright on iPhone.

![The quest board, the hero screen, an item being dug up, and the satchel, in the iPhone Simulator](../docs/ios-screenshots.png)

It plays by exactly the same rules as the web version, and a save backed up from
either one loads in the other.

## What is in here

```
ios/
  Spade.xcodeproj   The Xcode project. One app target, no outside packages.
  Config/           Info.plist: the fonts, and a few settings.
  Core/             The rules of the game. Plain Swift, no screen code, with tests.
  Spade/
    Scene/          The 3D scene: hero, scenery, the dig-up, and the icon camera.
    UI/             The screens.
    Platform/       Sound, haptics, reminders, and the iCloud calls for families.
    Resources/      Fonts, plus the models and textures exported from the web app.
  ci/               The script that screenshots the app in the iPhone Simulator.
```

Three ideas hold it together:

- **One set of rules.** `Core` is a line-by-line port of `src/game`. The web app
  writes out a few hundred worked examples (`npm run ios:data`), and the Swift
  tests check that they get the same answers: same quests dealt, same loot, same
  levels, same save after a 45-day playthrough.
- **One set of models.** The hero, the items and the scenery are not redrawn for
  iPhone. `npm run ios:data` exports the web app's shapes into
  `Spade/Resources/models.json`, and SceneKit builds them from that.
- **Icons are photographs.** Every icon is a tiny picture of a 3D model, taken by
  a second camera inside the app (`Scene/IconForge.swift`).

After changing quests, items, models or rules in the web app, run `npm run ios:data`
from the repository root and commit what it changes.

## Families: parents, children and allowance

The first screen (and Settings) asks who the Spade is for: **just me**,
**parent or guardian**, or **child**. Only the iPhone app has this; the web
version stays a single-player game.

A parent and a child connect once, and after that the two phones keep each
other up to date through iCloud:

1. **The parent** opens the **Family** tab, adds a child, and sets quests: which
   board, whether it repeats, the XP (5 to 1,000) and, if they like, an allowance.
2. They tap **Invite …**. Apple's sharing sheet opens (the same one Notes and
   Reminders use), and they send the invite, for example by Messages.
3. **The child** taps the invite and chooses to open it in Spade, then taps
   **Join**. The quests appear at the top of their board.
4. From then on nothing has to be sent. New and changed quests reach the child's
   Spade by themselves, and the parent's Family tab shows each quest the child
   finishes, with the date and time.
5. For every new family completion, a guardian taps **It's done** or **Not done** before XP is earned,
   and **Paid** once they've paid in real life. The child's Spade shows that too.

Updates usually arrive within about 15 seconds while Spade is open, and when it
is next opened otherwise.

See [the update and testing guide](../docs/progression-update-testing.md) for additional guardians, repeat-day requests, the changelog and Chamber rewards. Additional guardians share a separate private record; the family owner must open Spade to relay updates to and from children.

### How it works

Think of a notebook with two pages for each child, kept in the parent's iCloud
and shared with that child only:

- **The parent's page** holds the quest list and the parent's decisions. Only
  the parent's phone writes on it.
- **The child's page** holds which quests were finished, and when. Only the
  child's phone writes on it.

Each phone writes its own page and reads the other one. Because a page has one
writer, the phones can never overwrite each other. That also makes offline use
simple: a change is saved on the phone first and goes up when it is back
online, and a page that arrives late or twice does no harm (an older parent's
page is ignored, and a finished quest that is already recorded is skipped).

| Situation | What happens |
| --- | --- |
| The child finishes a quest offline, and the parent deleted it meanwhile | No XP yet. The parent sees the completion using the archived quest, then approves or declines it. |
| The parent changed the XP or allowance meanwhile | The guardian's amounts when the completion is first received determine XP and allowance. XP is paid only after approval. |
| The parent approves while the child is offline | The child sees it at the next sync. |
| The child leaves the family, or the parent removes them | Sharing stops. |

The parent's phone is the record of what is owed. The child's page only says
which quests were done; the amounts always come from the parent's copy. Spade
never moves real money.

There is no server of ours in this. The pages live in the parent's own iCloud
(Apple's CloudKit, in the app's private container), and Apple delivers them to
the one iCloud account that was invited. One phone per person: two phones on
the same Apple ID don't merge.

**Photo proof.** A parent can turn on **Ask for a photo** for a quest. The child
then takes or picks a photo before that quest counts. The photo stays on the
child's phone; the parent's Family tab says that one was taken, and the child
can send it from **Allowance** through the share sheet. (Photos are not part of
what iCloud keeps in step yet.)

**If something goes wrong.** Settings has an **iCloud sync** line, under "Who
this Spade is for". It shows when the last sync worked, or the reason it
didn't, including Apple's own error text. Tapping it checks again.

The rules live in `Core/Sources/SpadeCore/Family.swift`, with tests in
`Core/Tests/SpadeCoreTests/FamilyTests.swift` that play two phones against a
pretend iCloud. The iCloud calls are in `Spade/Platform/CloudFamily.swift`, and
the screens in `Spade/UI/FamilyView.swift`.

## Checking it without a Mac

Every pull request that touches `ios/` runs `.github/workflows/ios.yml`:

- **rules** runs the Swift rule tests on Linux.
- **app** builds the app on a Mac, opens each screen in the iPhone Simulator (a
  current iPhone, then a small one), and saves screenshots. It fails if the 3D
  scene comes out blank on any screen that shows it. Then it makes the same
  release build Codemagic makes, without signing it. The screenshots and build
  logs are under the run's **Artifacts**.

iCloud itself can't be checked there: the test Macs have no Apple ID. The family
rules are tested against a pretend iCloud; the real thing has to be tried on
two iPhones (see "Trying families on two iPhones" below).

With a Mac: open `ios/Spade.xcodeproj` in Xcode 16 or newer and press Run.
The rule tests run anywhere Swift is installed: `swift test --package-path ios/Core`.

## Getting it onto TestFlight with Codemagic

[Codemagic](https://codemagic.io) builds and signs the app on its Macs, using the
`codemagic.yaml` file at the top of this repository, and uploads it to App Store
Connect. No Mac is needed.

The first build needs some one-time setup. It is mostly making four things and
telling Codemagic about them. Think of it as getting a parcel through customs:
Apple wants to know who is sending it (the **certificate**), what it is (the
**App ID**), a permit that ties those two together (the **provisioning profile**),
and somewhere for it to land (the **app record**).

You need an [Apple Developer Program](https://developer.apple.com/programs/)
membership. Apple only lets adults enrol, so if you are under 18 a parent or
guardian has to own the account and do the Apple steps with you.

### 1. Apple: register the App ID

1. Go to <https://developer.apple.com/account> and open **Certificates, IDs & Profiles**.
2. Open **Identifiers** and press **+**.
3. Choose **App IDs**, then **App**.
4. Description: `Spade`. Bundle ID: **Explicit**, `com.huzkeymil.spade`.
5. Press **Continue**, then **Register**. (The two capabilities Spade needs are
   added in "Turning on iCloud" below.)

> The bundle ID is the app's permanent name inside Apple's systems. To use a
> different one, change it in three places: `PRODUCT_BUNDLE_IDENTIFIER` (twice) in
> `ios/Spade.xcodeproj/project.pbxproj`, `bundle_identifier` in `codemagic.yaml`,
> and `BUNDLE_ID` in `ios/ci/screenshots.sh`.

### 2. App Store Connect: make an API key

This key is what lets Codemagic talk to Apple for you. Treat it like a password.

1. Go to <https://appstoreconnect.apple.com/access/integrations/api>
   (**Users and Access → Integrations → App Store Connect API**).
2. Press **+**. Name: `Codemagic`. Access: **App Manager**. Press **Generate**.
3. Press **Download API Key**. It can only be downloaded once, so keep the `.p8` file safe.
4. Note the **Issuer ID** (above the table) and the **Key ID** (in the key's row).

### 3. App Store Connect: make the app record

1. Go to <https://appstoreconnect.apple.com/apps> and press **+ → New App**.
2. Platform: **iOS**.
3. Name: this is the App Store name and has to be unique across the whole store.
   Plain "Spade" is probably taken, so use something like `Spade: Side Quests`.
   (The name under the icon on the phone stays "Spade" either way.)
4. Primary language: yours. Bundle ID: pick `com.huzkeymil.spade` from the list.
5. SKU: anything, for example `spade-001`. User Access: **Full Access**. Press **Create**.

### 4. Codemagic: add the repository and the key

1. Sign in at <https://codemagic.io> with GitHub.
2. **Add application**, pick this repository, and choose **iOS App** as the project type.
3. Open **Teams → (your team or Personal Account) → Team integrations → Developer Portal → Connect**.
4. Key name: `spade`. This must match `app_store_connect: spade` in `codemagic.yaml`.
5. Enter the Issuer ID and Key ID from step 2, upload the `.p8` file, and press **Save**.

### 5. Codemagic: make the certificate

1. In the same team settings, open **codemagic.yaml settings → Code signing identities → iOS certificates**.
2. Press **Generate certificate**.
3. Reference name: `spade-distribution`. Type: **Apple Distribution**. Key: `spade`.
4. Press **Create certificate**. Download the file it offers and note the password
   (it is shown only once), then upload that file in the same tab so Codemagic keeps it.

### 6. Apple, then Codemagic: make the provisioning profile

1. Back at <https://developer.apple.com/account>, open **Profiles** and press **+**.
2. Under **Distribution**, choose **App Store Connect**. Continue.
3. App ID: `com.huzkeymil.spade`. Continue.
4. Tick the distribution certificate you just made. Continue.
5. Name: `Spade App Store`. Press **Generate**. (No need to download it.)
6. In Codemagic, open **Code signing identities → iOS provisioning profiles → Fetch profiles**.
7. Tick `Spade App Store`, give it the reference name `spade-app-store`, and press **Download selected**.
   A green tick in the **Certificate** column means it found its matching certificate.

### Turning on iCloud (for families)

Families sync through iCloud, which needs two capabilities on the App ID and
one small piece of setup in Apple's CloudKit Console. The app's signing files
have to match, so do steps 1 to 4 in one sitting: between steps 2 and 4,
Codemagic builds fail.

**At <https://developer.apple.com/account> → Certificates, IDs & Profiles**

1. **Identifiers** → **+** → **iCloud Containers** → Continue.
   Description: `Spade`. Identifier: `iCloud.com.huzkeymil.spade`. Register.
   This name is permanent: Apple doesn't let containers be deleted.
2. **Identifiers** → `com.huzkeymil.spade`.
   - Tick **iCloud**, choose the option that includes **CloudKit**, press
     **Configure** (or **Edit**), tick `iCloud.com.huzkeymil.spade`, and save.
   - Tick **Push Notifications**. (This is how iCloud tells the phones that
     something changed. Spade shows no notifications because of it.)
   - Press **Save** and confirm.
3. **Profiles** → `Spade App Store` → **Edit** → **Save** (or Generate).
   Changing capabilities makes the old profile invalid, so it has to be made again.

**In Codemagic**

4. **Code signing identities → iOS provisioning profiles**: delete
   `spade-app-store`, press **Fetch profiles**, tick `Spade App Store`, and give
   it the same reference name, `spade-app-store`. The certificate and the API
   key stay as they are.

**In the CloudKit Console**, at <https://icloud.developer.apple.com>

5. Open **CloudKit Database** and choose the container `iCloud.com.huzkeymil.spade`.
6. Make sure **Development** is selected at the top. Open **Schema → Record Types**.
7. Press **+**, name the new type `FamilyPage` (exactly that), and save.
8. In `FamilyPage`, add one field: name `body`, type **String**. Save.
9. Enable sharing in Development so Apple creates the system `cloudkit.share` type, then press **Deploy Schema Changes…** and deploy to **Production**. If that type is missing, use a temporary private setup zone in the Console, configure zone-wide sharing there, and deploy the schema. Do not switch the app's `SpadeFamily` zone to zone-wide sharing: it uses separate per-child shares.

Step 9 matters: TestFlight and App Store builds only talk to Production, and
Production refuses record types it hasn't been told about. Fields can be added
there later but never removed, which is why Spade uses a single small type.

> To use a different container name, change it in two places:
> `ios/Config/Spade.entitlements` and `containerId` in
> `ios/Spade/Platform/CloudFamily.swift`.

### 7. Build

1. In Codemagic, open the app and press **Start new build**.
2. Branch: `main`. Workflow: **Spade to TestFlight**. Press **Start new build**.

The build takes around ten minutes. When it finishes, Codemagic uploads the app
to App Store Connect.

### 8. Install it from TestFlight

1. In App Store Connect, open the app and go to the **TestFlight** tab.
   The build appears after Apple finishes processing it, usually within half an hour.
2. Under **Internal Testing**, press **+** to make a group, and add yourself.
3. On your iPhone, install the **TestFlight** app, sign in with the same Apple
   account, and install Spade from there.

Internal testers (people on your App Store Connect team) need no review.
To invite people outside the team, fill in **Test Information** in TestFlight,
make an external group, and Apple will review the first build, usually within a day.

### Trying families on two iPhones

Before starting:

- Each phone is signed in to iCloud with a **different** Apple ID, with iCloud
  Drive switched on. (A share can't be sent to the account that made it.)
- Both phones have the same TestFlight build. A second Apple ID that isn't on
  the App Store Connect team needs an external-tester invite, and Apple reviews
  the first external build (about a day).

Then:

1. **Parent's phone:** choose Parent or guardian, add a child, add two quests,
   tap **Invite …**, and send the invite to the child's iMessage address.
2. **Child's phone:** tap the invite, open it in Spade, tap **Join**. Both
   quests should be on the board, and the parent's card should say **Connected**.
3. **Parent:** add a third quest. It should reach the child's phone within about
   15 seconds.
4. **Child:** finish a quest. The parent's Family tab should show it.
5. **Offline:** put the child's phone in Airplane Mode and finish a quest. On the
   parent's phone, edit one quest and delete another. Turn Airplane Mode off and
   compare with the table in "How it works".
6. **Signed out:** sign out of iCloud on one phone. Settings → iCloud sync in
   Spade should say why it can't sync.

If a step fails, open Spade's Settings on that phone and send a screenshot of
the **iCloud sync** line and the text under it.

### Later builds

Start a new build in Codemagic. Nothing else is needed: each build stamps itself
with the date and time as its build number, so it always counts as newer.
To change the version people see (1.0, 1.1, ...), edit `MARKETING_VERSION` in
`ios/Spade.xcodeproj/project.pbxproj`.

### If a build fails

| The log says | What it means |
| --- | --- |
| `No matching profiles found for bundle identifier` | The profile from step 6 is missing in Codemagic, or its bundle ID differs from `com.huzkeymil.spade`. |
| `App Store Connect API key ... not found` or `integration` errors | The key name in step 4 is not `spade`. Rename it, or change `codemagic.yaml` to match. |
| `No suitable application records were found` | The app record from step 3 does not exist yet, or uses a different bundle ID. |
| `You already have a current Distribution certificate` | Apple allows three distribution certificates. Remove an old one at developer.apple.com, or fetch the existing one into Codemagic. |
| `The bundle version must be higher than the previously uploaded version` | A build with a later date was already uploaded. Start the build again. |
| `Provisioning profile ... doesn't include the com.apple.developer.icloud-...` or `aps-environment` entitlement | iCloud or Push Notifications isn't ticked on the App ID, or the profile wasn't made again and re-fetched afterwards ("Turning on iCloud", steps 2 to 4). |

And if the app builds but families don't sync, Spade's Settings → **iCloud sync** says why:

| It says | What it means |
| --- | --- |
| `Cannot create new type FamilyPage in production schema` (or similar) | The record type wasn't deployed to Production ("Turning on iCloud", steps 5 to 9). |
| This iPhone isn't signed in to iCloud | Sign in from the Settings app, and switch iCloud Drive on. |
| This build of Spade isn't set up for iCloud | The build was signed without the iCloud capability. Redo steps 2 to 4 and build again. |

## Sending it to the App Store

TestFlight builds and App Store builds are the same file. When the app is ready:
in App Store Connect, open the **Distribution** tab, fill in the listing
(screenshots, description, age rating, privacy answers), choose a build, and
press **Add for Review**. Spade has no accounts and no server of its own.
Family quests are stored in the parent's own iCloud and shared only with the
child they invite, with a separate family record shared with invited guardians; the developer can't read them. Check Apple's current
wording when answering the privacy questions, and mention iCloud in the review
notes.
