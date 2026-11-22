import Foundation
import Testing
@testable import MacToolkit

@MainActor
@Suite("AppSettings")
struct AppSettingsTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AppSettingsTests-\(UUID().uuidString)")!
    }

    @Test func thermalDefaults() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.thermalEnabled == false)
        #expect(settings.thermalAlertsEnabled == true)
    }

    @Test func thermalChoicesPersist() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.thermalEnabled = true
        settings.thermalAlertsEnabled = false

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.thermalEnabled == true)
        #expect(reloaded.thermalAlertsEnabled == false)
    }
}
