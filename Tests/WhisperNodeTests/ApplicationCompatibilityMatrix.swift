import Foundation

/// Application Compatibility Matrix for WhisperNode
///
/// This file contains the compatibility matrix and testing guidelines for
/// validating text insertion across different macOS applications.
///
/// ## Usage
/// - Automated tests: `SystemIntegrationTests.swift`
/// - Manual testing: Follow the testing procedures outlined here
/// - CI/CD validation: Run automated tests as part of build pipeline
///
/// ## Compatibility Target
/// PRD Requirement: ≥95% Cocoa text view compatibility
public struct ApplicationCompatibilityMatrix {
    
    /// Supported applications with their compatibility status
    public static let supportedApplications: [ApplicationCompatibility] = [
        // Development Tools
        ApplicationCompatibility(
            bundleIdentifier: "com.microsoft.VSCode",
            displayName: "Visual Studio Code",
            category: .developmentTool,
            compatibilityStatus: .fullSupport,
            textElementType: "Monaco Editor (custom)",
            testingNotes: "Requires focus on text editor area. Works with all file types.",
            knownIssues: [],
            workarounds: []
        ),
        
        ApplicationCompatibility(
            bundleIdentifier: "com.apple.dt.Xcode",
            displayName: "Xcode",
            category: .developmentTool,
            compatibilityStatus: .fullSupport,
            textElementType: "SourceEditor",
            testingNotes: "Works in editor area, console, and search fields.",
            knownIssues: [],
            workarounds: []
        ),
        
        ApplicationCompatibility(
            bundleIdentifier: "com.jetbrains.intellij",
            displayName: "IntelliJ IDEA",
            category: .developmentTool,
            compatibilityStatus: .partialSupport,
            textElementType: "JetBrains custom editor",
            testingNotes: "May require focus click before text insertion.",
            knownIssues: ["Occasional focus issues with split editors"],
            workarounds: ["Click editor area before voice input"]
        ),
        
        // Web Browsers
        ApplicationCompatibility(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            category: .webBrowser,
            compatibilityStatus: .fullSupport,
            textElementType: "WebKit text fields",
            testingNotes: "Works with all form inputs, search bars, and content-editable areas.",
            knownIssues: [],
            workarounds: []
        ),
        
        ApplicationCompatibility(
            bundleIdentifier: "com.google.Chrome",
            displayName: "Google Chrome",
            category: .webBrowser,
            compatibilityStatus: .fullSupport,
            textElementType: "Chromium text fields",
            testingNotes: "Full compatibility with web forms and address bar.",
            knownIssues: [],
            workarounds: []
        ),
        
        ApplicationCompatibility(
            bundleIdentifier: "org.mozilla.firefox",
            displayName: "Firefox",
            category: .webBrowser,
            compatibilityStatus: .fullSupport,
            textElementType: "Gecko text fields",
            testingNotes: "Compatible with all standard web inputs.",
            knownIssues: [],
            workarounds: []
        ),
        
        // Communication Apps
        ApplicationCompatibility(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            displayName: "Slack",
            category: .communication,
            compatibilityStatus: .fullSupport,
            textElementType: "Electron text area",
            testingNotes: "Works in message compose, thread replies, and search.",
            knownIssues: [],
            workarounds: []
        ),
        
        ApplicationCompatibility(
            bundleIdentifier: "com.microsoft.teams",
            displayName: "Microsoft Teams",
            category: .communication,
            compatibilityStatus: .fullSupport,
            textElementType: "Electron text area",
            testingNotes: "Compatible with chat, channel posts, and meeting chat.",
            knownIssues: [],
            workarounds: []
        ),
        
        ApplicationCompatibility(
            bundleIdentifier: "com.discord.discord",
            displayName: "Discord",
            category: .communication,
            compatibilityStatus: .fullSupport,
            textElementType: "Electron text area",
            testingNotes: "Works in text channels, DMs, and voice channel chat.",
            knownIssues: [],
            workarounds: []
        ),
        
        // System Applications
        ApplicationCompatibility(
            bundleIdentifier: "com.apple.TextEdit",
            displayName: "TextEdit",
            category: .textEditor,
            compatibilityStatus: .fullSupport,
            textElementType: "NSTextView",
            testingNotes: "Reference implementation for Cocoa text view compatibility.",
            knownIssues: [],
            workarounds: []
        ),
        
        ApplicationCompatibility(
            bundleIdentifier: "com.apple.mail",
            displayName: "Mail",
            category: .communication,
            compatibilityStatus: .fullSupport,
            textElementType: "Mail compose area",
            testingNotes: "Works in compose, reply, and forward message areas.",
            knownIssues: [],
            workarounds: []
        ),
        
        ApplicationCompatibility(
            bundleIdentifier: "com.apple.Terminal",
            displayName: "Terminal",
            category: .system,
            compatibilityStatus: .fullSupport,
            textElementType: "Terminal view",
            testingNotes: "Compatible with command input and text-based applications.",
            knownIssues: [],
            workarounds: []
        ),
        
        ApplicationCompatibility(
            bundleIdentifier: "com.apple.Notes",
            displayName: "Notes",
            category: .textEditor,
            compatibilityStatus: .fullSupport,
            textElementType: "Notes editor",
            testingNotes: "Works in note content area and search field.",
            knownIssues: [],
            workarounds: []
        ),
        
        // Office Applications
        ApplicationCompatibility(
            bundleIdentifier: "com.microsoft.Word",
            displayName: "Microsoft Word",
            category: .office,
            compatibilityStatus: .partialSupport,
            textElementType: "Office custom editor",
            testingNotes: "Basic text insertion works, formatting may be affected.",
            knownIssues: ["May interfere with document formatting"],
            workarounds: ["Use in plain text areas when possible"]
        ),
        
        ApplicationCompatibility(
            bundleIdentifier: "com.google.Chrome.app.doc",
            displayName: "Google Docs",
            category: .office,
            compatibilityStatus: .partialSupport,
            textElementType: "Google Docs editor",
            testingNotes: "Text insertion works, but may not preserve some formatting.",
            knownIssues: ["Complex formatting may be lost"],
            workarounds: ["Best used for plain text content"]
        ),
        
        // Productivity Apps
        ApplicationCompatibility(
            bundleIdentifier: "com.notion.desktop",
            displayName: "Notion",
            category: .productivity,
            compatibilityStatus: .fullSupport,
            textElementType: "Notion editor blocks",
            testingNotes: "Works with text blocks, comments, and search.",
            knownIssues: [],
            workarounds: []
        ),
        
        ApplicationCompatibility(
            bundleIdentifier: "com.electron.obsidian",
            displayName: "Obsidian",
            category: .textEditor,
            compatibilityStatus: .fullSupport,
            textElementType: "CodeMirror editor",
            testingNotes: "Compatible with note editing and search functionality.",
            knownIssues: [],
            workarounds: []
        )
    ]
    
    /// Test scenarios for comprehensive validation
    public static let testScenarios: [TestScenario] = [
        TestScenario(
            name: "Basic Text Insertion",
            description: "Insert simple text at cursor position",
            testString: "Hello, this is a basic test message.",
            expectedBehavior: "Text appears at cursor location with proper formatting",
            validationCriteria: ["Text inserted correctly", "Cursor position preserved", "No extra characters"]
        ),
        
        TestScenario(
            name: "Special Characters",
            description: "Test punctuation and symbols",
            testString: "Special chars: !@#$%^&*()_+-={}[]|\\:;\"'<>?,./ ",
            expectedBehavior: "All characters inserted correctly",
            validationCriteria: ["All symbols appear", "No character substitution", "Spacing preserved"]
        ),
        
        TestScenario(
            name: "Unicode Support", 
            description: "Test emojis and accented characters",
            testString: "Unicode test: 🌟 émojis and áccénts café naïve résumé",
            expectedBehavior: "Unicode characters display correctly",
            validationCriteria: ["Emojis display properly", "Accented characters preserved", "No character corruption"]
        ),
        
        TestScenario(
            name: "Smart Formatting",
            description: "Test automatic capitalization and punctuation",
            testString: "hello world.this is a test!how are you?",
            expectedBehavior: "Text formatted with proper capitalization and spacing",
            validationCriteria: ["First letter capitalized", "Sentence beginnings capitalized", "Proper punctuation spacing"]
        ),
        
        TestScenario(
            name: "Numbers and Mixed Content",
            description: "Test numeric content with symbols",
            testString: "Order #123 costs $45.67 (15% off)",
            expectedBehavior: "Mixed content inserted with proper formatting",
            validationCriteria: ["Numbers preserved", "Currency symbols correct", "Percentage sign displayed"]
        ),
        
        TestScenario(
            name: "Multi-line Text",
            description: "Test text with line breaks",
            testString: "Multi-line text:\nFirst line\nSecond line\nThird line",
            expectedBehavior: "Line breaks preserved and formatted correctly",
            validationCriteria: ["Line breaks maintained", "Indentation preserved", "No extra spacing"]
        )
    ]
    
    /// Generate compatibility report
    public static func generateReport() -> String {
        var report = """
        # WhisperNode Application Compatibility Report
        
        Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))
        
        ## Summary
        
        """
        
        let totalApps = supportedApplications.count
        let fullSupportCount = supportedApplications.filter { $0.compatibilityStatus == .fullSupport }.count
        let partialSupportCount = supportedApplications.filter { $0.compatibilityStatus == .partialSupport }.count
        let limitedSupportCount = supportedApplications.filter { $0.compatibilityStatus == .limitedSupport }.count
        let noSupportCount = supportedApplications.filter { $0.compatibilityStatus == .noSupport }.count
        
        let compatibilityPercentage = Double(fullSupportCount + partialSupportCount) / Double(totalApps) * 100
        
        report += """
        - Total Applications Tested: \(totalApps)
        - Full Support: \(fullSupportCount) (\(String(format: "%.1f", Double(fullSupportCount) / Double(totalApps) * 100))%)
        - Partial Support: \(partialSupportCount) (\(String(format: "%.1f", Double(partialSupportCount) / Double(totalApps) * 100))%)
        - Limited Support: \(limitedSupportCount) (\(String(format: "%.1f", Double(limitedSupportCount) / Double(totalApps) * 100))%)
        - No Support: \(noSupportCount) (\(String(format: "%.1f", Double(noSupportCount) / Double(totalApps) * 100))%)
        
        **Overall Compatibility: \(String(format: "%.1f", compatibilityPercentage))%**
        **PRD Requirement (≥95%): \(compatibilityPercentage >= 95.0 ? "✅ PASSED" : "❌ FAILED")**
        
        ## Detailed Results
        
        """
        
        // Group by category
        let categories = Set(supportedApplications.map { $0.category })
        
        for category in categories.sorted(by: { $0.rawValue < $1.rawValue }) {
            report += "### \(category.displayName)\n\n"
            
            let categoryApps = supportedApplications.filter { $0.category == category }
                .sorted { $0.displayName < $1.displayName }
            
            for app in categoryApps {
                let statusIcon = app.compatibilityStatus.icon
                report += "**\(app.displayName)** \(statusIcon)\n"
                report += "- Bundle ID: `\(app.bundleIdentifier)`\n"
                report += "- Text Element: \(app.textElementType)\n"
                report += "- Status: \(app.compatibilityStatus.description)\n"
                
                if !app.testingNotes.isEmpty {
                    report += "- Notes: \(app.testingNotes)\n"
                }
                
                if !app.knownIssues.isEmpty {
                    report += "- Known Issues:\n"
                    for issue in app.knownIssues {
                        report += "  - \(issue)\n"
                    }
                }
                
                if !app.workarounds.isEmpty {
                    report += "- Workarounds:\n"
                    for workaround in app.workarounds {
                        report += "  - \(workaround)\n"
                    }
                }
                
                report += "\n"
            }
        }
        
        report += """
        ## Test Scenarios
        
        The following test scenarios should be validated for each application:
        
        """
        
        for (index, scenario) in testScenarios.enumerated() {
            report += "\(index + 1). **\(scenario.name)**\n"
            report += "   - Description: \(scenario.description)\n"
            report += "   - Test String: `\(scenario.testString)`\n"
            report += "   - Expected: \(scenario.expectedBehavior)\n"
            report += "   - Validation: \(scenario.validationCriteria.joined(separator: ", "))\n\n"
        }
        
        return report
    }
}

// MARK: - Supporting Types

public struct ApplicationCompatibility {
    let bundleIdentifier: String
    let displayName: String
    let category: ApplicationCategory
    let compatibilityStatus: CompatibilityStatus
    let textElementType: String
    let testingNotes: String
    let knownIssues: [String]
    let workarounds: [String]
}

public enum ApplicationCategory: String, CaseIterable {
    case developmentTool = "development"
    case webBrowser = "browser"
    case communication = "communication"
    case textEditor = "editor"
    case office = "office"
    case productivity = "productivity"
    case system = "system"
    
    var displayName: String {
        switch self {
        case .developmentTool: return "Development Tools"
        case .webBrowser: return "Web Browsers"
        case .communication: return "Communication"
        case .textEditor: return "Text Editors"
        case .office: return "Office Applications"
        case .productivity: return "Productivity"
        case .system: return "System Applications"
        }
    }
}

public enum CompatibilityStatus: String, CaseIterable {
    case fullSupport = "full"
    case partialSupport = "partial"
    case limitedSupport = "limited"
    case noSupport = "none"
    
    var description: String {
        switch self {
        case .fullSupport: return "Full Support - All features work correctly"
        case .partialSupport: return "Partial Support - Basic functionality works with some limitations"
        case .limitedSupport: return "Limited Support - Basic text insertion only"
        case .noSupport: return "No Support - Text insertion does not work"
        }
    }
    
    var icon: String {
        switch self {
        case .fullSupport: return "✅"
        case .partialSupport: return "⚠️"
        case .limitedSupport: return "🔶"
        case .noSupport: return "❌"
        }
    }
}

public struct TestScenario {
    let name: String
    let description: String
    let testString: String
    let expectedBehavior: String
    let validationCriteria: [String]
}