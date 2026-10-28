import AppIntents

// Compiled into both the app and the widget extension. Apple requires an
// intent that opens the app from a control to be a member of both targets;
// the system then runs it inside the app.

/// The screen a control opens.
enum DailySpendDestination: String, AppEnum {
    case add
    case scan

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Screen"
    static let caseDisplayRepresentations: [DailySpendDestination: DisplayRepresentation] = [
        .add: "New Expense",
        .scan: "Receipt Scanner"
    ]

    /// Set by the app at launch; opens the screen once Home allows it.
    @MainActor static var openHandler: ((DailySpendDestination) -> Void)?
}

/// Opens DailySpend from a Control Center, Lock Screen, or Action button control.
struct OpenDailySpendIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open DailySpend"
    static let isDiscoverable = false

    @Parameter(title: "Screen")
    var target: DailySpendDestination

    init() {}

    init(target: DailySpendDestination) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        DailySpendDestination.openHandler?(target)
        return .result()
    }
}
