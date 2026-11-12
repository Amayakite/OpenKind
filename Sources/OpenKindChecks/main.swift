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
