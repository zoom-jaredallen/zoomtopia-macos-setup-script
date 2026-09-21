import SwiftUI

struct ContentView: View {
    @StateObject private var controller = SetupController()

    var body: some View {
        Group {
            switch controller.phase {
            case .setup:
                setupView
            case .permissions:
                PermissionAssistantView(controller: controller)
            case .ready:
                readyView
            }
        }
        .background(ZoomtopiaTheme.canvas)
        .foregroundStyle(ZoomtopiaTheme.primaryText)
        .tint(ZoomtopiaTheme.actionBlue)
        .preferredColorScheme(.dark)
        .alert("Setup needs attention", isPresented: $controller.showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(controller.errorMessage)
        }
    }

    private var setupView: some View {
        VStack(spacing: 0) {
            header
            BrandedDivider()
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(controller.steps) { step in
                        StepRow(step: step)
                    }
                }
                .padding(24)
            }
            BrandedDivider()
            footer
        }
    }

    private var header: some View {
        BrandedHeader(
            title: "Technical Connect · Mac Setup",
            subtitle: controller.summary,
            progress: controller.isPreparing ? controller.downloadProgress : controller.isRunning ? controller.progress : nil
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Offline Payload…") { controller.chooseOfflinePayload() }
                .disabled(controller.isRunning)
            if controller.offlinePayloadURL != nil {
                Button("Use Online Downloads") { controller.offlinePayloadURL = nil }
                    .disabled(controller.isRunning)
            }
            if controller.isPreparing {
                Button("Cancel Download") { controller.cancelPreparation() }
            }
            Button("Open Log") { controller.openLog() }
                .disabled(!controller.logExists)
            if controller.hasActionRequired && controller.provisioningPassed {
                Button("Permission Assistant") { controller.showPermissionAssistant() }
                    .disabled(!controller.isComplete)
            }
            Spacer()
            Button(controller.isComplete ? "Run Again" : "Start Setup") {
                controller.start()
            }
            .buttonStyle(.borderedProminent)
            .tint(ZoomtopiaTheme.actionBlue)
            .controlSize(.large)
            .disabled(controller.isRunning)
        }
        .padding(20)
        .background(ZoomtopiaTheme.footer)
    }

    private var readyView: some View {
        VStack(spacing: 26) {
            Spacer()
            ZoomtopiaWordmark(width: 270)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 78))
                .foregroundStyle(ZoomtopiaTheme.success)
            VStack(spacing: 8) {
                Text("This Mac is ready")
                    .font(.largeTitle.bold())
                Text("Automated setup passed and the operator confirmed Zoom camera, microphone, screen sharing, and audio output.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ZoomtopiaTheme.secondaryText)
                    .frame(maxWidth: 560)
            }
            HStack(spacing: 12) {
                Button("View Setup Summary") { controller.returnToSetupSummary() }
                Button("Run Zoom Test Again") { controller.openZoomTest() }
                    .buttonStyle(.borderedProminent)
                    .tint(ZoomtopiaTheme.actionBlue)
            }
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [ZoomtopiaTheme.brandNavy, ZoomtopiaTheme.canvas, Color.blue.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct StepRow: View {
    let step: SetupStep

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            statusIcon
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.headline)
                if !step.detail.isEmpty {
                    Text(step.detail)
                        .font(.subheadline)
                        .foregroundStyle(ZoomtopiaTheme.secondaryText)
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(ZoomtopiaTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ZoomtopiaTheme.border))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch step.state {
        case .pending:
            Image(systemName: "circle").foregroundStyle(Color.white.opacity(0.28))
        case .running:
            ProgressView().controlSize(.small)
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(ZoomtopiaTheme.success)
        case .skipped:
            Image(systemName: "minus.circle.fill").foregroundStyle(ZoomtopiaTheme.secondaryText)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(ZoomtopiaTheme.warning)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(ZoomtopiaTheme.failure)
        case .actionRequired:
            Image(systemName: "person.crop.circle.badge.exclamationmark").foregroundStyle(ZoomtopiaTheme.warning)
        }
    }
}

private struct PermissionAssistantView: View {
    @ObservedObject var controller: SetupController

    var body: some View {
        VStack(spacing: 0) {
            permissionHeader
            BrandedDivider()
            ScrollView {
                VStack(spacing: 16) {
                    introCard
                    PermissionCard(
                        id: "camera",
                        title: "Camera",
                        detail: "Start the Zoom test meeting, turn video on, and choose Allow when macOS asks for camera access.",
                        icon: "video.fill",
                        confirmed: binding(for: "camera"),
                        primaryTitle: "Start Zoom Test",
                        primaryAction: controller.openZoomTest,
                        secondaryTitle: "Open Camera Settings",
                        secondaryAction: controller.openCameraSettings
                    )
                    PermissionCard(
                        id: "microphone",
                        title: "Microphone",
                        detail: "In the Zoom test meeting, join computer audio and choose Allow when macOS asks for microphone access.",
                        icon: "mic.fill",
                        confirmed: binding(for: "microphone"),
                        primaryTitle: "Open Zoom",
                        primaryAction: controller.launchZoom,
                        secondaryTitle: "Open Microphone Settings",
                        secondaryAction: controller.openMicrophoneSettings
                    )
                    screenRecordingCard
                    PermissionCard(
                        id: "audio-test",
                        title: "Speakers and audio output",
                        detail: "Speakers do not require a macOS privacy grant. Use Zoom’s speaker test and confirm that sound is audible.",
                        icon: "speaker.wave.3.fill",
                        confirmed: binding(for: "audio-test"),
                        primaryTitle: "Run Zoom Test",
                        primaryAction: controller.openZoomTest
                    )
                }
                .padding(24)
            }
            BrandedDivider()
            permissionFooter
        }
        .background(
            LinearGradient(
                colors: [ZoomtopiaTheme.canvas, ZoomtopiaTheme.brandNavy.opacity(0.90), Color.blue.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var permissionHeader: some View {
        BrandedHeader(
            title: "Technical Connect · Zoom Permissions",
            subtitle: "Complete the required privacy approvals and functional tests."
        )
    }

    private var introCard: some View {
        HStack(spacing: 16) {
            zoomIcon
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 5) {
                Text("Complete each test in Zoom Workplace")
                    .font(.headline)
                Text("These checkboxes are operator confirmations. macOS does not let this setup app silently grant or inspect another app’s private permissions.")
                    .font(.subheadline)
                    .foregroundStyle(ZoomtopiaTheme.secondaryText)
            }
            Spacer()
            Button("Open Zoom") { controller.launchZoom() }
                .buttonStyle(.borderedProminent)
                .tint(ZoomtopiaTheme.actionBlue)
        }
        .padding(18)
        .background(ZoomtopiaTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ZoomtopiaTheme.border))
    }

    private var screenRecordingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(ZoomtopiaTheme.actionBlue)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Screen & System Audio Recording")
                        .font(.headline)
                    Text("Open Screen Recording settings. If Zoom is not listed, drag the Zoom tile below into the application list, enable it, then restart Zoom.")
                        .font(.subheadline)
                        .foregroundStyle(ZoomtopiaTheme.secondaryText)
                }
                Spacer()
                Toggle("Completed", isOn: binding(for: "screen-recording"))
                    .toggleStyle(.checkbox)
            }
            HStack(spacing: 12) {
                ZoomDragTile(url: controller.zoomApplicationURL)
                Image(systemName: "arrow.right")
                    .foregroundStyle(ZoomtopiaTheme.secondaryText)
                Button("Open Screen Recording Settings") { controller.openScreenRecordingSettings() }
                    .buttonStyle(.borderedProminent)
                    .tint(ZoomtopiaTheme.actionBlue)
                Button("Restart Zoom") {
                    NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").forEach { $0.terminate() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { controller.launchZoom() }
                }
            }
            .padding(.leading, 44)
        }
        .padding(18)
        .background(ZoomtopiaTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ZoomtopiaTheme.border))
    }

    private var permissionFooter: some View {
        HStack {
            Button("Back to Setup Summary") { controller.returnToSetupSummary() }
            Spacer()
            Text(controller.allPermissionStepsConfirmed ? "All Zoom checks confirmed" : "Complete all four checks")
                .font(.subheadline)
                .foregroundStyle(ZoomtopiaTheme.secondaryText)
            Button("Mark Mac Ready") { controller.finishPermissionAssistant() }
                .buttonStyle(.borderedProminent)
                .tint(ZoomtopiaTheme.actionBlue)
                .controlSize(.large)
                .disabled(!controller.allPermissionStepsConfirmed)
        }
        .padding(20)
        .background(ZoomtopiaTheme.footer)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { controller.confirmedPermissionIDs.contains(id) },
            set: { controller.setPermissionConfirmed(id, confirmed: $0) }
        )
    }

    @ViewBuilder
    private var zoomIcon: some View {
        if let url = controller.zoomApplicationURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "video.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(ZoomtopiaTheme.actionBlue)
        }
    }
}

private struct PermissionCard: View {
    let id: String
    let title: String
    let detail: String
    let icon: String
    @Binding var confirmed: Bool
    let primaryTitle: String
    let primaryAction: () -> Void
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(ZoomtopiaTheme.actionBlue)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(ZoomtopiaTheme.secondaryText)
                }
                Spacer()
                Toggle("Completed", isOn: $confirmed)
                    .toggleStyle(.checkbox)
            }
            HStack(spacing: 10) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .tint(ZoomtopiaTheme.actionBlue)
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                }
            }
            .padding(.leading, 44)
        }
        .padding(18)
        .background(ZoomtopiaTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ZoomtopiaTheme.border))
    }
}

private struct ZoomDragTile: View {
    let url: URL?

    var body: some View {
        HStack(spacing: 9) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "video.circle.fill")
                    .font(.title2)
                    .foregroundStyle(ZoomtopiaTheme.actionBlue)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Zoom Workplace")
                    .font(.subheadline.bold())
                Text(url == nil ? "Install Zoom first" : "Drag into System Settings")
                    .font(.caption)
                    .foregroundStyle(ZoomtopiaTheme.secondaryText)
            }
            Image(systemName: "hand.draw")
                .foregroundStyle(ZoomtopiaTheme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ZoomtopiaTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ZoomtopiaTheme.border))
        .onDrag {
            guard let url else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
        }
        .opacity(url == nil ? 0.55 : 1)
    }
}
