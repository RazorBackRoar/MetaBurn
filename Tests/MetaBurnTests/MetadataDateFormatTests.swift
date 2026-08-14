import Foundation
import MetaBurnCore
import Testing

@Suite("MetadataDateFormat")
struct MetadataDateFormatTests {
    @Test("EXIF timestamps display as mm/dd/yyyy")
    func exifDate() {
        #expect(MetadataDateFormat.display("2026:08:13 18:58:38") == "08/13/2026")
        #expect(MetadataDateFormat.display("2026:08:13") == "08/13/2026")
    }

    @Test("ISO and hyphen dates display as mm/dd/yyyy")
    func isoDate() {
        #expect(MetadataDateFormat.display("2026-08-13") == "08/13/2026")
        #expect(MetadataDateFormat.display("2026-08-13 18:58:38") == "08/13/2026")
    }

    @Test("already mm/dd/yyyy stays mm/dd/yyyy")
    func alreadyFormatted() {
        #expect(MetadataDateFormat.display("08/13/2026") == "08/13/2026")
        #expect(MetadataDateFormat.display("8/13/2026") == "08/13/2026")
    }

    @Test("empty input stays empty")
    func empty() {
        #expect(MetadataDateFormat.display("") == "")
        #expect(MetadataDateFormat.display("   ") == "")
    }
}
