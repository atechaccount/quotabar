import Foundation

/// Ports `providers/credential-selection.js`'s `selectCredential`. Used by the
/// Codex reader, whose OAuth store's stored `exp` claim is advisory only: only
/// an empirical request against the provider's own endpoint may produce a
/// definitive rejection, so "expired" candidates are tried too (after "valid"
/// ones), never assumed dead.
enum NQCredentialSelection {
    enum LocalState { case valid, expired }

    struct Candidate<Credentials> {
        let source: String
        let localState: LocalState
        let refreshable: Bool?
        let credentials: Credentials

        init(source: String, localState: LocalState, refreshable: Bool? = nil, credentials: Credentials) {
            self.source = source
            self.localState = localState
            self.refreshable = refreshable
            self.credentials = credentials
        }
    }

    enum AttemptOutcome<Success> {
        case quota(Success)
        case liveNoQuota
        case rejected(error: String)
        case transient(error: String, retryAfter: String?)
    }

    struct SelectedCandidate {
        let source: String
        let localState: LocalState
        let refreshable: Bool?
    }

    struct CandidateResult {
        let source: String
        var outcome: String
        var error: String?
    }

    enum SelectionOutcome<Success> {
        case quota(winner: SelectedCandidate, result: Success, results: [CandidateResult])
        case liveNoQuota(winner: SelectedCandidate, transientError: String?, retryAfter: String?, results: [CandidateResult])
        case transient(error: String, retryAfter: String?, results: [CandidateResult])
        case allRejected(results: [CandidateResult])
        case noCandidates(results: [CandidateResult])
    }

    static func select<Credentials, Success>(
        candidates: [Candidate<Credentials>],
        attempt: (Candidate<Credentials>) async -> AttemptOutcome<Success>
    ) async -> SelectionOutcome<Success> {
        let ordered = candidates.filter { $0.localState == .valid } + candidates.filter { $0.localState == .expired }
        var results = ordered.map { CandidateResult(source: $0.source, outcome: "not_tried", error: nil) }
        var liveWinner: SelectedCandidate?
        var transientError: String?
        var retryAfter: String?
        var tried = 0
        var rejectedCount = 0

        for (index, candidate) in ordered.enumerated() {
            tried += 1
            let outcome = await attempt(candidate)
            switch outcome {
            case let .quota(success):
                results[index].outcome = "quota"
                return .quota(winner: selected(candidate), result: success, results: results)
            case .liveNoQuota:
                results[index].outcome = "live_no_quota"
                if liveWinner == nil { liveWinner = selected(candidate) }
                continue
            case let .rejected(error):
                results[index].outcome = "rejected"
                results[index].error = error
                rejectedCount += 1
                continue
            case let .transient(error, after):
                results[index].outcome = "transient"
                results[index].error = error
                transientError = error
                retryAfter = after
            }
            break
        }

        if let liveWinner {
            return .liveNoQuota(winner: liveWinner, transientError: transientError, retryAfter: retryAfter, results: results)
        }
        if let transientError {
            return .transient(error: transientError, retryAfter: retryAfter, results: results)
        }
        if tried > 0 && rejectedCount == tried {
            return .allRejected(results: results)
        }
        return .noCandidates(results: results)
    }

    private static func selected<Credentials>(_ candidate: Candidate<Credentials>) -> SelectedCandidate {
        SelectedCandidate(source: candidate.source, localState: candidate.localState, refreshable: candidate.refreshable)
    }
}
