# Family and Chamber update

## What changed

- Mythic Marl is the last named rank, beginning at level 100. Levels continue beyond 100.
- Every new family completion needs guardian approval for XP, loot and completion achievements. This includes quests with no allowance. Declining awards nothing. Old completions retain XP already awarded by previous builds.
- Guardians see an activity changelog. The old completion list remains, limited to the three newest completions. The separate pending-approval queue still shows every quest waiting to be checked.
- A repeating quest can land on a selected weekday. Selecting a weekday makes it a weekly quest. Without a weekday it keeps its daily, weekly or monthly cadence. One-off quests are unchanged.
- Children request another weekday through their Family quests/Allowance sheet. A request can be permanent or only for the current week. A guardian must approve it. A one-time request expires when its week ends or its requested day has passed. Moving an already-completed occurrence cannot earn its XP again.
- The Chamber in Settings contains Dogger at 500,000 XP, The Spade at 1 million and Spade Green at 2.5 million. Rewards must be claimed in order.

## Additional guardians

The family owner taps **Invite another guardian** in Family, selects private invited-person sharing with write access, and sends the invitation. The recipient opens it in Spade and accepts **Join as a guardian**. Use a separate iCloud account for each person. **Manage guardians** opens Apple's participant controls, including removal.

Guardians can add/edit quests, review completions, approve XP, manage allowance records and answer schedule requests. The owner sends child invites.

**Current delivery limitation:** keep the owner's Spade open to relay changes between the guardians' shared record and each child's private records. Additional guardians do not directly write child shares. Opening the owner and child apps catches up queued changes. This avoids sharing other children's pages with a child, but is not a server-backed relay and does not promise instant background delivery.

Concurrent guardian writes use CloudKit record-change checks and merge only changed fields. Unrelated edits survive. The first synced approval/decline for a completion or schedule request wins. Guardians on the same Apple ID/multiple devices are not supported as separate people.

Guardian data uses the existing `FamilyPage.body` schema and a separate private CKShare, so an already-working production sharing setup needs no new record type. Leaving a guardian family removes that participant's share access; the owner leaving ends the guardian share and child shares.

## Developer testing

In a Debug or TestFlight build, open **Settings → Locked: Chamber of Completion → Developer testing**. Password: `marlin-digs`.

Use **Test unlock this reward** on any reward. It also unlocks preceding rewards, persists the items/colour and leaves lifetime XP unchanged. Equip Dogger in Hero → Charm and The Spade in Hero → Hand. Spade Green is the last skin/hair/scarf swatch. Developer access must be unlocked again after relaunching.

Back up the save first if you want to restore the locked state later. The developer UI is hidden in the production App Store build. This password is a testing convenience, not an account or security credential.

## Physical-device acceptance checks

Use the same new TestFlight build on an owner, a second guardian and a child, each signed into a different iCloud account.

1. Complete a family quest with zero allowance. XP, loot and completion counts must stay unchanged until approval. Approve it, sync and verify one payout. Repeat sync, then mark an allowance claim paid: no second XP payout.
2. Decline another completion. Verify it awards no XP. Confirm previously earned XP remains after updating from an older build.
3. Create a repeating quest for today. Check it appears on the weekly board. Request another day once, approve it and verify it returns to the original day the following week. Repeat with a permanent request. Test declining and an expired request.
4. Invite the second guardian. Edit different quests on both guardian phones while offline, reconnect, open the owner and child apps, and verify both edits survive. Give conflicting decisions on one claim; verify the first synced decision remains and XP pays once.
5. Test guardian removal and leaving. Confirm the removed account can no longer sync the family. Verify child shares still work when an additional guardian leaves.
6. Complete four quests and confirm the compact list shows only the newest three, while activity appears in the changelog and all pending approvals remain accessible.
7. Test all three Chamber rewards, equip both items and each green colour. Relaunch and verify ownership. On an untouched save, verify claims are blocked below their thresholds and out of sequence.
8. Test while signed out of iCloud and offline; verify the app reports the issue and retains pending changes. Do not erase the save to troubleshoot sync.

Automated checks cover the game rules, web/native parity, native compilation and simulator rendering. They cannot verify Apple's live sharing permissions or delivery across physical iCloud accounts. Before App Review, record the actual new build and update review notes to describe CloudKit, guardians and approval-based XP.
