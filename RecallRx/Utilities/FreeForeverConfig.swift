import Foundation
import StoreKit

/// Immutable RecallRx Core Feature Entitlement Policy
/// All features listed in `freeForeverFeatures` are guaranteed to remain free forever
/// with zero subscription, zero paywalls, and zero cloud API fees.
/// Any alteration to this file or the free tier requires explicit owner sign-off.
struct FreeForeverConfig: Sendable {
    
    /// The canonical list of free-forever capabilities
    static let freeForeverFeatures: [String] = [
        "Core Flashcard Review & Study",
        "FSRS-6 Algorithm (21 Parameters) & On-Device Optimizer",
        "Classic SM-2 Algorithm & Load Balancer",
        "Hands-Free Driving Mode (On-Device Speech Synthesis & Recognition)",
        "Anki .apkg Archive & Media Importer with Deduplication",
        "Full Automated Rolling Local Backups & 100% History Restore",
        "Medical Image Occlusion Creator & SVG Diagram Studio",
        "QBank Fast-Unsuspend (UWorld, AMBOSS, NBME Tokens)",
        "Bluetooth Remote & Gamepad Study Mode (8BitDo, Joy-Con)",
        "Hierarchical tag explorer (:: delimiters)",
        "Interactive One-by-One Cloze Deletion Engine",
        "Shelf Exam Cram Dynamic Filtered Decks & Exam Pacing",
        "iOS 17 Home & Lock Screen Widgets and Due Count Badges",
        "Offline On-Device AI PDF & Lecture Slide Note Extraction"
    ]
    
    /// Features eligible for optional premium upgrade (StoreKit 2)
    static let premiumOptionalFeatures: [String] = [
        "CloudKit Multi-Device Cross-Platform Sync",
        "Optional Cloud LLM Synthesis (OpenAI / Claude API Opt-In)",
        "Multi-Institution Shared Deck Live Subscriptions"
    ]
    
    /// Verification guard ensuring no free feature is accidentally marked premium
    static func isFreeForever(featureName: String) -> Bool {
        return freeForeverFeatures.contains(where: { $0.localizedCaseInsensitiveContains(featureName) })
    }
}

/// StoreKit 2 Manager providing regional localized pricing and optional premium subscriptions
@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()
    
    // Product IDs for optional cloud extensions
    static let cloudSyncMonthlyID = "com.recallrx.subscription.cloudsync.monthly"
    static let cloudSyncYearlyID = "com.recallrx.subscription.cloudsync.yearly"
    
    @Published private(set) var availableProducts: [Product] = []
    @Published private(set) var hasCloudSyncEntitlement: Bool = false
    @Published private(set) var purchaseInProgress: Bool = false
    @Published var errorMessage: String?
    
    private var updatesTask: Task<Void, Never>?
    
    private init() {
        // Local-first default: Check existing entitlements
        Task {
            await updatePurchasedEntitlements()
            await fetchProducts()
        }
        observeTransactionUpdates()
    }
    
    deinit {
        updatesTask?.cancel()
    }
    
    /// Fetches products from App Store with localized regional currencies
    func fetchProducts() async {
        do {
            let products = try await Product.products(for: [
                Self.cloudSyncMonthlyID,
                Self.cloudSyncYearlyID
            ])
            self.availableProducts = products.sorted(by: { $0.price < $1.price })
        } catch {
            print("[StoreKit] Error fetching products: \(error.localizedDescription)")
            // Provide fallback simulated local products if running in simulator without StoreKit config file
            #if DEBUG
            self.hasCloudSyncEntitlement = UserDefaults.standard.bool(forKey: "simulated_cloud_sync_entitlement")
            #endif
        }
    }
    
    /// Purchases an optional cloud extension with StoreKit 2
    func purchase(_ product: Product) async -> Bool {
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await updatePurchasedEntitlements()
                    return true
                case .unverified(_, let error):
                    self.errorMessage = "Transaction verification failed: \(error.localizedDescription)"
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                self.errorMessage = "Purchase pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
    
    /// Restores previous purchases
    func restorePurchases() async {
        try? await AppStore.sync()
        await updatePurchasedEntitlements()
    }
    
    /// Checks active entitlements
    func updatePurchasedEntitlements() async {
        var cloudSyncActive = false
        
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.revocationDate == nil {
                    if transaction.productID == Self.cloudSyncMonthlyID || transaction.productID == Self.cloudSyncYearlyID {
                        cloudSyncActive = true
                    }
                }
            }
        }
        
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "simulated_cloud_sync_entitlement") {
            cloudSyncActive = true
        }
        #endif
        
        self.hasCloudSyncEntitlement = cloudSyncActive
    }
    
    private func observeTransactionUpdates() {
        updatesTask = Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.updatePurchasedEntitlements()
                }
            }
        }
    }
}
