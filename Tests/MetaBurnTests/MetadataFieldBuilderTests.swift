import Testing
@testable import MetaBurn

@Suite("Metadata fields")
struct MetadataFieldBuilderTests {
    @Test("photo table includes make, model, camera, GPS, and mm/dd/yyyy dates")
    @MainActor
    func requiredPhotoFields() {
        let before = [
            MetadataEntry(group: "EXIF", tag: "Make", value: "Apple"),
            MetadataEntry(group: "EXIF", tag: "Model", value: "iPhone 16 Pro"),
            MetadataEntry(group: "EXIF", tag: "DateTimeOriginal", value: "2026:08:13 18:58:38"),
            MetadataEntry(group: "File", tag: "FileModifyDate", value: "2026:08:13 19:00:00"),
            MetadataEntry(group: "GPS", tag: "GPSPosition", value: "37.774900, -122.419400")
        ]
        let rows = MetadataFieldBuilder.buildRows(
            filePath: "/tmp/photo.jpg",
            before: before,
            after: []
        )
        let byLabel = Dictionary(uniqueKeysWithValues: rows.map { ($0.label, $0) })

        #expect(byLabel["Make"]?.before == "Apple")
        #expect(byLabel["Model"]?.before == "iPhone 16 Pro")
        #expect(byLabel["Camera"]?.before == "Apple iPhone 16 Pro")
        #expect(byLabel["GPS Location"]?.before == "37.774900, -122.419400")
        #expect(byLabel["Date Created"]?.before == "08/13/2026")
        #expect(byLabel["Date Modified"]?.before == "08/13/2026")
        #expect(byLabel["Software"] == nil)
    }
}
