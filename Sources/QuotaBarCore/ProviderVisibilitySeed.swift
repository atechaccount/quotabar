import Foundation

/// The answer to "why is everything enabled?".
///
/// Provider visibility used to be an empty exclusion set, so every provider
/// quota-axi mentioned was on - including the eight that cannot be read at all.
/// The first successful snapshot now decides it once: providers with fresh,
/// measurable quota start on, everything else starts off. The seed is computed
/// from that snapshot rather than from a hard-coded provider list, so a machine
/// signed into a different set of providers gets the right answer too.
public enum ProviderVisibilitySeed {
    /// The providers to *hide* on first launch, given the first real snapshot.
    /// Returns `nil` when the snapshot cannot decide anything yet, so the caller
    /// waits for a better one instead of seeding a set it would regret.
    public static func hiddenProviders(from snapshot: QuotaSnapshot?) -> Set<String>? {
        guard let providers = snapshot?.providers, !providers.isEmpty else { return nil }
        // Nothing measurable anywhere means quota-axi has not really reported yet
        // (no CLI, no credentials at all). Hiding everything would leave an empty
        // app with no way back in, so leave the decision for a later snapshot.
        guard providers.contains(where: { $0.availability.isMeasurable }) else { return nil }
        return Set(providers.filter { !$0.availability.isMeasurable }.map(\.provider))
    }
}
