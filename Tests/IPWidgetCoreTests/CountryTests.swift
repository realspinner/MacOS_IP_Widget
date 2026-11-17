import Foundation
import Testing
@testable import IPWidgetCore

@Suite("Countries and flags")
struct CountryTests {
    @Test func flagEmojiFromISOCode() {
        #expect(Country.flagEmoji(forISOCode: "SE") == "🇸🇪")
        #expect(Country.flagEmoji(forISOCode: "se") == "🇸🇪")
        #expect(Country.flagEmoji(forISOCode: " US ") == "🇺🇸")
        #expect(Country.flagEmoji(forISOCode: "RU") == "🇷🇺")
    }

    @Test func invalidCodesProduceGlobe() {
        #expect(Country.flagEmoji(forISOCode: nil) == "🌐")
        #expect(Country.flagEmoji(forISOCode: "") == "🌐")
        #expect(Country.flagEmoji(forISOCode: "S") == "🌐")
        #expect(Country.flagEmoji(forISOCode: "SWE") == "🌐")
        #expect(Country.flagEmoji(forISOCode: "S1") == "🌐")
        #expect(Country.flagEmoji(forISOCode: "XX") == "🌐")
    }

    @Test func localizedCountryNames() {
        let english = Locale(identifier: "en_US")
        let russian = Locale(identifier: "ru_RU")
        #expect(Country.localizedName(forISOCode: "SE", locale: english) == "Sweden")
        #expect(Country.localizedName(forISOCode: "se", locale: russian) == "Швеция")
        #expect(Country.localizedName(forISOCode: nil, locale: english) == nil)
        #expect(Country.localizedName(forISOCode: "X", locale: english) == nil)
    }

    @Test func geoInfoNormalizesCodeAndFallsBackToAPIName() throws {
        let ip = try #require(IPv4Address(canonicalizing: "45.159.12.7"))
        let geo = GeoInfo(ip: ip, countryCode: " se ", countryName: "  Sweden  ")
        #expect(geo.countryCode == "SE")
        #expect(geo.countryName == "Sweden")
        #expect(geo.flag == "🇸🇪")
        #expect(geo.localizedCountryName(locale: Locale(identifier: "en_US")) == "Sweden")

        let unknown = GeoInfo(ip: ip, countryCode: nil, countryName: "Atlantis")
        #expect(unknown.flag == "🌐")
        #expect(unknown.localizedCountryName(locale: Locale(identifier: "en_US")) == "Atlantis")
    }

    @Test func geoInfoIgnoresBlankCountryName() throws {
        let ip = try #require(IPv4Address(canonicalizing: "45.159.12.7"))
        let geo = GeoInfo(ip: ip, countryCode: "SE", countryName: "   ")
        #expect(geo.countryName == nil)
        #expect(geo.localizedCountryName(locale: Locale(identifier: "en_US")) == "Sweden")
    }
}
