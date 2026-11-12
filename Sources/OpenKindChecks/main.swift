import Foundation
import OpenKindCore

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
check(FileCatalog.normalize(" .DOCX \n") == "docx", "normalize extension")
check(FileCatalog.normalize("7z") == "7z", "accept digits")
check(FileCatalog.normalize("") == nil, "reject empty extension")
check(FileCatalog.normalize("a/b") == nil, "reject slash")
check(FileCatalog.normalize("x y") == nil, "reject spaces")
let list = FileCatalog.all(custom: ["DOCX", ".zzz", "zzz", "bad/path"])
check(list.filter { $0 == "docx" }.count == 1, "deduplicate built-in")
check(list.filter { $0 == "zzz" }.count == 1, "deduplicate custom extensions")
check(!list.contains("bad/path"), "discard invalid extensions")
check(list == list.sorted(), "sort extensions")
check(FileCatalog.category(for: "docx") == .documents, "document category")
check(FileCatalog.category(for: "xlsx") == .spreadsheets, "spreadsheet category")
check(FileCatalog.category(for: "custom") == .other, "custom category")
print("OpenKind checks passed")
check(FileCatalog.category(for: "vue") == .frontend, "Vue category")
check(FileCatalog.category(for: "tsx") == .frontend, "TSX category")
check(FileCatalog.category(for: "jsonc") == .configuration, "JSONC category")
do { try await runAIChecks() } catch { fputs("FAIL: AI checks: \(error)\n", stderr); exit(1) }
let candidates: Set<String> = ["/Applications/WordCraft.app"]
check(ChangeGuard.evaluate(expectedType: "type.docx", actualType: "type.docx", expectedCurrent: "/Applications/Old.app", actualCurrent: "/Applications/Old.app", target: "/Applications/WordCraft.app", candidates: candidates, targetExists: true) == .allowed, "approve unchanged supported association")
check(ChangeGuard.evaluate(expectedType: "type.docx", actualType: "type.docx", expectedCurrent: "/Applications/Old.app", actualCurrent: "/Applications/New.app", target: "/Applications/WordCraft.app", candidates: candidates, targetExists: true) == .currentChanged, "reject changed current app")
check(ChangeGuard.evaluate(expectedType: "type.docx", actualType: "type.other", expectedCurrent: nil, actualCurrent: nil, target: "/Applications/WordCraft.app", candidates: candidates, targetExists: true) == .typeChanged, "reject changed system type")
check(ChangeGuard.evaluate(expectedType: "type.docx", actualType: "type.docx", expectedCurrent: nil, actualCurrent: nil, target: "/Applications/Missing.app", candidates: candidates, targetExists: false) == .missingApplication, "reject missing app")
check(ChangeGuard.evaluate(expectedType: "type.docx", actualType: "type.docx", expectedCurrent: nil, actualCurrent: nil, target: "/Applications/Other.app", candidates: candidates, targetExists: true) == .unsupportedApplication, "reject unsupported app")
print("Association preflight checks passed")
check(AppLanguage.usesChinese(.system, preferredLanguages: ["zh-Hans-CN"]), "follow Chinese system language")
check(!AppLanguage.usesChinese(.system, preferredLanguages: ["en-US"]), "follow English system language")
check(AppLanguage.usesChinese(.simplifiedChinese, preferredLanguages: ["en"]), "explicit Chinese overrides system")
check(!AppLanguage.usesChinese(.english, preferredLanguages: ["zh"]), "explicit English overrides system")
let oldConfig = ProviderConfiguration(mode: .compatible, baseURL: "https://legacy.example/v1", model: "old-model")
let migrated = ProviderRegistry.initial(legacy: [oldConfig], activeMode: .compatible)
check(migrated.profiles.count == 3, "migrate legacy profile and add presets")
let legacyProfile = migrated.profiles.first { $0.config == oldConfig }!
check(migrated.activeID == legacyProfile.id, "preserve active migrated profile")
let oldAccount = try legacyProfile.credentialAccount()
let legacyEndpoint = try oldConfig.endpoint("").absoluteString
check(oldAccount == "\(oldConfig.mode.rawValue)|\(legacyEndpoint)", "preserve legacy credential account")
var changedProfile = legacyProfile
changedProfile.config.baseURL = "https://other.example/v1"
let changedAccount = try changedProfile.credentialAccount()
check(changedAccount != oldAccount, "do not reuse key after endpoint change")
let anotherProfile = ProviderProfile(name: "Other", config: oldConfig)
let anotherAccount = try anotherProfile.credentialAccount()
check(anotherAccount != oldAccount, "isolate keys between profiles")
let deepseek = ProviderProfile.deepSeek()
let deepseekModelsURL = try deepseek.config.endpoint("models")
check(deepseekModelsURL.absoluteString == "https://api.deepseek.com/models", "DeepSeek model endpoint")
print("Language and provider migration checks passed")
do { try runDiscoveryChecks() } catch { fputs("FAIL: app discovery checks: \(error)\n", stderr); exit(1) }
check(ChangeGuard.evaluate(expectedType: "type.docx", actualType: "type.docx", expectedCurrent: nil, actualCurrent: nil, target: "/Applications/Other.app", candidates: candidates, targetExists: true, allowUnregistered: true) == .allowed, "allow explicitly selected unregistered target")
check(ChangeGuard.evaluate(expectedType: "type.docx", actualType: "type.docx", expectedCurrent: "old", actualCurrent: "changed", target: "/Applications/Other.app", candidates: candidates, targetExists: true, allowUnregistered: true) == .currentChanged, "unregistered override cannot bypass stale-state guard")
let aliasProposals = [ChangeProposal(fileExtension: "htm", typeID: "public.html", target: "/App", current: "/Old"), ChangeProposal(fileExtension: "html", typeID: "public.html", target: "/App", current: "/Old"), ChangeProposal(fileExtension: "vue", typeID: "vue", target: "/App", current: nil)]
let groupedAliases = try ChangeGrouping.group(aliasProposals)
check(groupedAliases == [["htm", "html"], ["vue"]], "group aliases into one system write")
do { _ = try ChangeGrouping.group([aliasProposals[0], ChangeProposal(fileExtension: "html", typeID: "public.html", target: "/Other", current: "/Old")]); fputs("FAIL: conflicting target accepted\n", stderr); exit(1) } catch ChangeGroupingError.conflictingTargets { }
do { _ = try ChangeGrouping.group([aliasProposals[0], ChangeProposal(fileExtension: "html", typeID: "public.html", target: "/App", current: "/Changed")]); fputs("FAIL: inconsistent state accepted\n", stderr); exit(1) } catch ChangeGroupingError.inconsistentCurrent { }
print("Association grouping checks passed")
