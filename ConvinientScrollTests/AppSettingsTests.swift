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

    @Test func appsChoicesPersist() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.appsEnabled == true)
        #expect(settings.appsWatchEnabled == true)
        #expect(settings.appsHiddenIDs == [])
        settings.appsEnabled = false
        settings.appsWatchEnabled = false
        settings.appsHiddenIDs = ["com.example.chatter"]

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.appsEnabled == false)
        #expect(reloaded.appsWatchEnabled == false)
        #expect(reloaded.appsHiddenIDs == ["com.example.chatter"])
    }
}
