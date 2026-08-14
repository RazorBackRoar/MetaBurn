import AppKit
import SwiftUI

struct MetaBurnFireImage: View {
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "flame.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(MetaBurnTheme.accent)
            }
        }
        .accessibilityHidden(true)
    }

    private var image: NSImage? {
        guard let url = Resources.url(forResource: "HeaderFire", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
