import AppKit
import SwiftUI

enum ZoomtopiaTheme {
    static let brandNavy = Color(red: 0.0, green: 5.0 / 255.0, blue: 61.0 / 255.0)
    static let canvas = Color(red: 7.0 / 255.0, green: 12.0 / 255.0, blue: 35.0 / 255.0)
    static let surface = Color(red: 15.0 / 255.0, green: 23.0 / 255.0, blue: 52.0 / 255.0)
    static let raisedSurface = Color(red: 21.0 / 255.0, green: 32.0 / 255.0, blue: 68.0 / 255.0)
    static let footer = Color(red: 9.0 / 255.0, green: 15.0 / 255.0, blue: 40.0 / 255.0)
    static let border = Color.white.opacity(0.10)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.68)
    static let actionBlue = Color(red: 47.0 / 255.0, green: 119.0 / 255.0, blue: 1.0)
    static let success = Color(red: 70.0 / 255.0, green: 211.0 / 255.0, blue: 132.0 / 255.0)
    static let warning = Color(red: 1.0, green: 180.0 / 255.0, blue: 65.0 / 255.0)
    static let failure = Color(red: 1.0, green: 91.0 / 255.0, blue: 102.0 / 255.0)
}

struct ZoomtopiaWordmark: View {
    var width: CGFloat = 238

    var body: some View {
        Group {
            if let image = Self.loadImage() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("zoomtopia")
                    .font(.system(size: 38, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: width, height: width * 270.0 / 1286.0, alignment: .leading)
        .accessibilityLabel("Zoomtopia")
    }

    private static func loadImage() -> NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("zoomtopia-wordmark.png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

struct BrandedHeader: View {
    let title: String
    let subtitle: String
    var progress: Double? = nil

    var body: some View {
        HStack(spacing: 28) {
            ZoomtopiaWordmark()
            Rectangle()
                .fill(Color.white.opacity(0.20))
                .frame(width: 1, height: 52)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(ZoomtopiaTheme.primaryText)
                Text(subtitle)
                    .foregroundStyle(ZoomtopiaTheme.secondaryText)
            }
            Spacer()
            if let progress {
                ProgressView(value: progress)
                    .tint(ZoomtopiaTheme.actionBlue)
                    .frame(width: 150)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(ZoomtopiaTheme.brandNavy)
    }
}

struct BrandedDivider: View {
    var body: some View {
        Rectangle()
            .fill(ZoomtopiaTheme.border)
            .frame(height: 1)
    }
}
