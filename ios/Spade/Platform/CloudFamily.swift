import CloudKit
import UIKit

// Families, in iCloud.
//
// Each child gets two small records ("pages") in a private corner of the
// parent's iCloud, shared with that child and nobody else:
//
//   p-<child id>   the parent's page   written only by the parent's phone
//   k-<child id>   the child's page    written only by the child's phone
//
// What goes on a page, and what to do with one that arrives, is decided by the
// rules in Core/Sources/SpadeCore/Family.swift. This file only carries pages
// to and from iCloud (Apple's CloudKit).
//
// Nothing here touches a server of ours. The pages are stored in the parent's
// own iCloud, and Apple delivers them to the one iCloud account that was invited.

/// A problem that deserves words of our own.
enum CloudProblem: Error {
    /// The pages aren't in iCloud: the invite was taken back, or was never made.
    case notShared
    /// The invite doesn't say where its pages are.
    case badInvite
    case familyTooLarge
}

/// A page as iCloud holds it: its text, and a tag that changes whenever the page does.
struct CloudPage {
    var body: String
    var tag: String?
}

final class CloudFamily {
    static let containerId = "iCloud.com.huzkeymil.spade"
    static let zoneName = "SpadeFamily"
    /// The one record type the app uses. It has to exist in the CloudKit Console (see ios/README.md).
    static let recordType = "FamilyPage"
    static let bodyKey = "body"
    /// What an invite is called. The child's Spade reads the parent's name back out of it.
    static let titlePrefix = "Spade quests from "

    let container: CKContainer
    private var listening: Set<String> = []

    init() {
        container = CKContainer(identifier: Self.containerId)
    }

    /// The parent's own iCloud.
    private var home: CKDatabase { container.privateCloudDatabase }
    /// What other people have shared with this iCloud account.
    private var shared: CKDatabase { container.sharedCloudDatabase }

    private var homeZone: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    private func sharedZone(_ link: CloudLink) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: link.zone, ownerName: link.owner)
    }

    private func parentPageID(_ kidId: String, in zone: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "p-\(kidId)", zoneID: zone)
    }

    private func kidPageID(_ kidId: String, in zone: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "k-\(kidId)", zoneID: zone)
    }

    /// A record, or nil if iCloud has no such record (or nowhere to keep it).
    private func find(_ id: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord? {
        do {
            return try await database.record(for: id)
        } catch let error as CKError where Self.meansMissing(error) {
            return nil
        }
    }

    private static func meansMissing(_ error: CKError) -> Bool {
        error.code == .unknownItem || error.code == .zoneNotFound || error.code == .userDeletedZone
    }

    private func page(_ record: CKRecord) -> CloudPage {
        CloudPage(body: record[Self.bodyKey] as? String ?? "", tag: record.recordChangeTag)
    }

    // MARK: - This iPhone's iCloud

    /// Nil if iCloud can be used right now. Otherwise, why not, in plain words.
    func unavailableReason() async -> String? {
        do {
            switch try await container.accountStatus() {
            case .available:
                return nil
            case .noAccount:
                return "This iPhone isn't signed in to iCloud. Sign in from the Settings app, then come back to Spade."
            case .restricted:
                return "iCloud is restricted on this iPhone, by Screen Time or by a profile."
            case .temporarilyUnavailable:
                return "iCloud isn't ready on this iPhone yet. The Settings app may be asking for your password."
            case .couldNotDetermine:
                return "Spade couldn't check iCloud. It will try again soon."
            @unknown default:
                return "iCloud isn't available right now."
            }
        } catch {
            return Self.describe(error)
        }
    }

    /// Asks iCloud to nudge this iPhone when a page changes, so updates arrive without waiting.
    /// The nudges are silent: they need no permission and show nothing.
    func listen(asParent: Bool) async {
        let id = asParent ? "spade-family-home" : "spade-family-shared"
        guard !listening.contains(id) else { return }
        let subscription = CKDatabaseSubscription(subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            _ = try await (asParent ? home : shared).save(subscription)
            listening.insert(id)
        } catch {
            // Not a disaster: the app also checks every few seconds while it is open.
        }
    }

    // MARK: - The parent's side

    /// Makes sure this child's two pages and their share exist, with the parent's
    /// page up to date, and returns the share (to hand to Apple's sharing sheet).
    func prepareShare(kidId: String, title: String, body: String) async throws -> CKShare {
        let zone = homeZone
        _ = try await home.save(CKRecordZone(zoneID: zone))

        let root = try await find(parentPageID(kidId, in: zone), in: home)
            ?? CKRecord(recordType: Self.recordType, recordID: parentPageID(kidId, in: zone))
        root[Self.bodyKey] = body
        var saving: [CKRecord] = [root]

        if try await find(kidPageID(kidId, in: zone), in: home) == nil {
            // An empty page for the child to write on. It hangs under the parent's page,
            // which is what puts it inside the share.
            let page = CKRecord(recordType: Self.recordType, recordID: kidPageID(kidId, in: zone))
            page[Self.bodyKey] = ""
            page.setParent(root)
            saving.append(page)
        }

        let share: CKShare
        if let reference = root.share, let existing = try await find(reference.recordID, in: home) as? CKShare {
            share = existing
        } else {
            share = CKShare(rootRecord: root)
            // Only people the parent invites, never "anyone with the link".
            share.publicPermission = .none
        }
        share[CKShare.SystemFieldKey.title] = title
        if let icon = Self.iconData { share[CKShare.SystemFieldKey.thumbnailImageData] = icon }
        saving.append(share)

        let results = try await home.modifyRecords(saving: saving, deleting: [])
        for result in results.saveResults.values {
            _ = try result.get()
        }
        if let stored = results.saveResults[share.recordID], let saved = try stored.get() as? CKShare {
            return saved
        }
        return share
    }

    /// The app's icon, to show on the invite.
    static var iconData: Data? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last,
              let image = UIImage(named: name)
        else { return nil }
        return image.pngData()
    }

    /// Puts the parent's page for this child in iCloud.
    func storeParentPage(kidId: String, body: String) async throws {
        guard let root = try await find(parentPageID(kidId, in: homeZone), in: home) else {
            throw CloudProblem.notShared
        }
        root[Self.bodyKey] = body
        _ = try await home.save(root)
    }

    /// The child's page, as the parent's phone sees it. Nil if it isn't there.
    func kidPage(kidId: String) async throws -> CloudPage? {
        guard let record = try await find(kidPageID(kidId, in: homeZone), in: home) else { return nil }
        return page(record)
    }

    /// Takes a child's pages and their share out of iCloud. The child's Spade stops receiving anything.
    func withdraw(kidId: String) async throws {
        let zone = homeZone
        var deleting = [kidPageID(kidId, in: zone), parentPageID(kidId, in: zone)]
        do {
            if let root = try await find(parentPageID(kidId, in: zone), in: home), let reference = root.share {
                deleting.insert(reference.recordID, at: 0)
            }
            let results = try await home.modifyRecords(saving: [], deleting: deleting, atomically: false)
            for result in results.deleteResults.values {
                // Something that was already gone is fine.
                if case .failure(let error) = result, let known = error as? CKError, !Self.meansMissing(known) {
                    throw error
                }
            }
        } catch let error as CKError where Self.meansMissing(error) {
            return
        }
    }

    // MARK: - The child's side

    /// Who an invite is from, in the words the parent's Spade gave it ("Sam"), or
    /// failing that the name on their iCloud account.
    static func sender(of invite: CKShare.Metadata) -> String {
        if let title = invite.share[CKShare.SystemFieldKey.title] as? String, title.hasPrefix(titlePrefix) {
            let name = String(title.dropFirst(titlePrefix.count)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        if let parts = invite.ownerIdentity.nameComponents {
            let name = PersonNameComponentsFormatter.localizedString(from: parts, style: .default)
            if !name.isEmpty { return name }
        }
        return "Your parent"
    }

    /// Where an invite's pages are kept, and which child they are for.
    static func place(of invite: CKShare.Metadata) -> (link: CloudLink, kidId: String)? {
        guard let root = invite.hierarchicalRootRecordID, root.recordName.hasPrefix("p-") else { return nil }
        var owner = root.zoneID.ownerName
        if owner == CKCurrentUserDefaultName, let named = invite.ownerIdentity.userRecordID?.recordName {
            owner = named
        }
        return (CloudLink(zone: root.zoneID.zoneName, owner: owner), String(root.recordName.dropFirst(2)))
    }

    /// Accepts an invite, and fetches the parent's page that comes with it.
    func join(_ invite: CKShare.Metadata) async throws -> (link: CloudLink, kidId: String, body: String) {
        guard let place = Self.place(of: invite) else { throw CloudProblem.badInvite }
        if invite.participantStatus != .accepted {
            _ = try await container.accept(invite)
        }
        // Just after accepting, iCloud can take a moment before the pages show up.
        var last: Error = CloudProblem.notShared
        for attempt in 0..<6 {
            if attempt > 0 { try await Task.sleep(for: .seconds(1.5)) }
            do {
                if let page = try await parentPage(link: place.link, kidId: place.kidId) {
                    return (place.link, place.kidId, page.body)
                }
            } catch {
                last = error
            }
        }
        throw last
    }

    /// The parent's page, as the child's phone sees it. Nil if it isn't shared with this iCloud account.
    func parentPage(link: CloudLink, kidId: String) async throws -> CloudPage? {
        guard let record = try await find(parentPageID(kidId, in: sharedZone(link)), in: shared) else { return nil }
        return page(record)
    }

    /// Puts the child's page in iCloud.
    func storeKidPage(link: CloudLink, kidId: String, body: String) async throws {
        let zone = sharedZone(link)
        let record: CKRecord
        if let existing = try await find(kidPageID(kidId, in: zone), in: shared) {
            record = existing
        } else {
            // The page went missing: add it again, under the parent's page.
            guard try await find(parentPageID(kidId, in: zone), in: shared) != nil else {
                throw CloudProblem.notShared
            }
            record = CKRecord(recordType: Self.recordType, recordID: kidPageID(kidId, in: zone))
            record.setParent(parentPageID(kidId, in: zone))
        }
        record[Self.bodyKey] = body
        _ = try await shared.save(record)
    }

    /// Leaves a family's share. The parent's pages stay where they are; this account just stops seeing them.
    func leave(link: CloudLink, kidId: String) async throws {
        guard let root = try await find(parentPageID(kidId, in: sharedZone(link)), in: shared),
              let reference = root.share
        else { return }
        _ = try await shared.deleteRecord(withID: reference.recordID)
    }

    // MARK: - Errors, in words

    /// An iCloud error in plain words, followed by Apple's own wording and code number.
    /// (The second part is for whoever is asked to help.)
    static func describe(_ error: Error) -> String {
        if let problem = error as? CloudProblem {
            switch problem {
            case .notShared: return "These quests aren't shared through iCloud any more. A new invite will fix that."
            case .familyTooLarge: return "This family has too much history to sync. Contact support before making more changes."
            case .badInvite: return "This invite doesn't look like one from Spade."
            }
        }
        guard var known = error as? CKError else { return error.localizedDescription }
        // When several things were saved together, the real reason is inside.
        if known.code == .partialFailure,
           let inner = known.partialErrorsByItemID?.values.compactMap({ $0 as? CKError }).first(where: { $0.code != .batchRequestFailed }) {
            known = inner
        }
        let plain: String
        switch known.code {
        case .notAuthenticated:
            plain = "This iPhone isn't signed in to iCloud."
        case .networkUnavailable, .networkFailure:
            plain = "There's no internet connection right now."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            plain = "iCloud is busy. Spade will try again soon."
        case .quotaExceeded:
            plain = "This iCloud account is out of storage."
        case .permissionFailure:
            plain = "iCloud didn't allow that for this account."
        case .unknownItem, .zoneNotFound, .userDeletedZone:
            plain = "The shared pages are missing from iCloud."
        case .participantMayNeedVerification:
            plain = "iCloud needs to check who you are. Open the invite again."
        case .badContainer, .missingEntitlement:
            plain = "This build of Spade isn't set up for iCloud."
        case .serverRecordChanged:
            plain = "The page changed while it was being saved. Spade will try again soon."
        case .accountTemporarilyUnavailable:
            plain = "iCloud isn't ready on this iPhone yet."
        default:
            plain = "iCloud couldn't do that."
        }
        return "\(plain) (iCloud said: \(known.localizedDescription) Code \(known.code.rawValue).)"
    }
}

// MARK: - Apple's sharing sheet

/// Apple's own sheet for sending an invite and, later, for seeing who has joined
/// or taking the invite back. It is the same one Notes and Reminders use.
@MainActor
enum InviteSheet {
    /// The sheet's delegate has to be kept alive while the sheet is up.
    private static var keeper: Keeper?

    static func present(
        share: CKShare,
        container: CKContainer,
        title: String,
        stopped: @escaping @MainActor () -> Void,
        failed: @escaping @MainActor (Error) -> Void
    ) {
        guard let top = Share.topViewController() else { return }
        let sheet = UICloudSharingController(share: share, container: container)
        // Private invites only, and the child has to be able to write their page.
        sheet.availablePermissions = [.allowPrivate, .allowReadWrite]
        let keeper = Keeper(title: title, stopped: stopped, failed: failed)
        Self.keeper = keeper
        sheet.delegate = keeper
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
    }

    private final class Keeper: NSObject, UICloudSharingControllerDelegate {
        let title: String
        let stopped: @MainActor () -> Void
        let failed: @MainActor (Error) -> Void

        init(title: String, stopped: @escaping @MainActor () -> Void, failed: @escaping @MainActor (Error) -> Void) {
            self.title = title
            self.stopped = stopped
            self.failed = failed
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            title
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            CloudFamily.iconData
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            let failed = failed
            Task { @MainActor in failed(error) }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            let stopped = stopped
            Task { @MainActor in stopped() }
        }
    }
}

extension CloudFamily {
    static func guardianPlace(_ invite: CKShare.Metadata) -> GuardianHub? {
        guard let root = invite.hierarchicalRootRecordID, root.recordName.hasPrefix("g-") else { return nil }
        let owner = root.zoneID.ownerName == CKCurrentUserDefaultName ? (invite.ownerIdentity.userRecordID?.recordName ?? root.zoneID.ownerName) : root.zoneID.ownerName
        return GuardianHub(record: root.recordName, cloud: CloudLink(zone: root.zoneID.zoneName, owner: owner))
    }

    func prepareGuardianShare(_ house: Household) async throws -> CKShare {
        _ = try await home.save(CKRecordZone(zoneID: homeZone))
        let id = CKRecord.ID(recordName: "g-" + house.familyId, zoneID: homeZone)
        let root: CKRecord
        if let found = try await find(id, in: home) { root = found }
        else {
            root = CKRecord(recordType: Self.recordType, recordID: id)
            root[Self.bodyKey] = String(decoding: try JSONEncoder().encode(GuardianDocument(household: house)), as: UTF8.self)
        }
        let share: CKShare
        if let reference = root.share, let existing = try await find(reference.recordID, in: home) as? CKShare { share = existing }
        else { share = CKShare(rootRecord: root); share.publicPermission = .none }
        share[CKShare.SystemFieldKey.title] = "Spade guardians"
        let result = try await home.modifyRecords(saving: [root, share], deleting: [])
        for item in result.saveResults.values { _ = try item.get() }
        return (try result.saveResults[share.recordID]?.get() as? CKShare) ?? share
    }

    func leaveGuardians(_ hub: GuardianHub) async throws {
        let database = hub.cloud == nil ? home : shared
        let zone = hub.cloud.map(sharedZone) ?? homeZone
        let id = CKRecord.ID(recordName: hub.record, zoneID: zone)
        guard let root = try await find(id, in: database) else { return }
        if let share = root.share { _ = try await database.deleteRecord(withID: share.recordID) }
        if hub.cloud == nil { _ = try await home.deleteRecord(withID: id) }
    }

    func joinGuardian(_ invite: CKShare.Metadata) async throws -> (GuardianHub, GuardianDocument) {
        guard let hub = Self.guardianPlace(invite) else { throw CloudProblem.badInvite }
        if invite.participantStatus != .accepted { _ = try await container.accept(invite) }
        for attempt in 0..<6 {
            if attempt > 0 { try await Task.sleep(for: .seconds(1.5)) }
            do { return (hub, try await syncGuardians(hub, changes: [])) }
            catch { if attempt == 5 { throw error } }
        }
        throw CloudProblem.notShared
    }

    func syncGuardians(_ hub: GuardianHub, changes: [GuardianChange]) async throws -> GuardianDocument {
        let database = hub.cloud == nil ? home : shared
        let zone = hub.cloud.map(sharedZone) ?? homeZone
        let id = CKRecord.ID(recordName: hub.record, zoneID: zone)
        for attempt in 0..<5 {
            guard let record = try await find(id, in: database), let body = record[Self.bodyKey] as? String else { throw CloudProblem.notShared }
            var document = try JSONDecoder().decode(GuardianDocument.self, from: Data(body.utf8))
            if changes.isEmpty { return document }
            for change in changes { document = mergeGuardianChange(change, into: document) }
            let data = try JSONEncoder().encode(document)
            guard data.count < 900_000 else { throw CloudProblem.familyTooLarge }
            record[Self.bodyKey] = String(decoding: data, as: UTF8.self)
            do {
                let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
                for item in result.saveResults.values { _ = try item.get() }
                return document
            } catch {
                let ck = error as? CKError
                let conflict = ck?.code == .serverRecordChanged || ck?.partialErrorsByItemID?.values.contains(where: { ($0 as? CKError)?.code == .serverRecordChanged }) == true
                if !conflict || attempt == 4 { throw error }
            }
        }
        throw CloudProblem.notShared
    }
}
