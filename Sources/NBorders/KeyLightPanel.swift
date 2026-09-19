import BordersCore
import SwiftUI

struct KeyLightPanel: View {
    @ObservedObject var controller: KeyLightStatusItemController

    private var store: KeyLightStore { controller.store }

    private let panelWidth: CGFloat = 380

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.primary.opacity(0.02))

            Divider()
                .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 14) {
                    EmergencyLightButton(
                        isLightsOff: controller.areAllLightsOff,
                        action: controller.toggleAllLights
                    )

                    SADLampButton(store: store)

                    BrightnessFeedbackSection(controller: controller.brightnessFeedback)

                    if store.devices.isEmpty {
                        PairingInstructions(store: store)
                    } else {
                        ForEach(store.devices) { device in
                            KeyLightCard(device: device, store: store)
                        }
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 520)

            Divider()
                .padding(.horizontal, 16)

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: panelWidth)
        .fixedSize(horizontal: true, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.yellow)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Key Lights")
                    .font(.system(size: 15, weight: .semibold))
                Text(store.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: store.refresh) {
                Image(systemName: store.isSearching ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .rotationEffect(.degrees(store.isSearching ? 180 : 0))
            }
            .buttonStyle(.borderless)
            .help("Refresh Key Light discovery")
            .accessibilityLabel("Refresh Key Light discovery")
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("Local network only · no telemetry")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

private struct BrightnessFeedbackSection: View {
    @ObservedObject var controller: KeyLightBrightnessFeedbackController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "camera.metering.center.weighted")
                    .foregroundStyle(.cyan)
                Text("Camera feedback")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { controller.isEnabled },
                    set: controller.setEnabled
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Text("Use the DocCam camera to gently steer the light towards a measured brightness. This is relative luminance, not calibrated lux.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if controller.cameraDevices.isEmpty {
                HStack(spacing: 8) {
                    Text("No USB camera found")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Refresh", action: controller.refreshCameras)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else {
                if controller.cameraDevices.count > 1 {
                    Picker("Camera", selection: Binding(
                        get: { controller.selectedCameraID ?? "" },
                        set: controller.selectCamera
                    )) {
                        ForEach(controller.cameraDevices) { camera in
                            Text(camera.name).tag(camera.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }

                FeedbackTargetSlider(controller: controller)

                Toggle("Lock camera exposure", isOn: Binding(
                    get: { controller.configuration.locksCameraExposure },
                    set: controller.setLocksCameraExposure
                ))
                .font(.system(size: 11))
                .toggleStyle(.checkbox)

                HStack(spacing: 6) {
                    Circle()
                        .fill(controller.isEnabled ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(controller.status)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button(action: controller.refreshCameras) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh camera list")
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.cyan.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.cyan.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera brightness feedback")
    }
}

private struct FeedbackTargetSlider: View {
    @ObservedObject var controller: KeyLightBrightnessFeedbackController

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "viewfinder")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text("Target")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            Slider(
                value: Binding(
                    get: { controller.configuration.targetLuminance },
                    set: controller.setTargetLuminance
                ),
                in: 0...1
            )
            .controlSize(.small)
            Text("\(controller.targetPercent)%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .frame(height: 22)
    }
}

private struct SADLampButton: View {
    @ObservedObject var store: KeyLightStore
    @State private var isHovering = false

    var body: some View {
        Button(action: store.activateSADLamp) {
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SAD Lamp")
                        .font(.system(size: 14, weight: .semibold))
                    Text("100% · \(KeyLightLimits.temperature.upperBound) K daylight")
                        .font(.system(size: 10))
                        .opacity(0.78)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(isHovering ? 1 : 0.88))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.devices.isEmpty)
        .opacity(store.devices.isEmpty ? 0.42 : 1)
        .onHover { isHovering = $0 }
        .help("Turn all discovered Key Lights on at full brightness and 7000 K")
        .accessibilityLabel("SAD lamp preset")
        .accessibilityValue(store.devices.isEmpty ? "No lights connected" : "Full brightness, 7000 Kelvin")
    }
}

private struct KeyLightCard: View {
    let device: KeyLightDevice
    @ObservedObject var store: KeyLightStore

    private var state: KeyLightState {
        store.state(for: device) ?? .sensibleDefault
    }

    private var hasState: Bool {
        store.state(for: device) != nil
    }

    private var visibleBrightness: Int {
        state.isOn ? max(KeyLightLimits.minimumVisibleBrightness, state.brightness) : 0
    }

    private var brightnessRange: ClosedRange<Double> {
        state.isOn
            ? Double(KeyLightLimits.minimumVisibleBrightness)...Double(KeyLightLimits.brightness.upperBound)
            : Double(KeyLightLimits.brightness.lowerBound)...Double(KeyLightLimits.brightness.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: state.isOn ? "lightbulb.fill" : "lightbulb.slash")
                    .foregroundStyle(state.isOn ? .yellow : .secondary)
                Text(device.name)
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { state.isOn },
                    set: { store.setPower($0, for: device) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!hasState)
            }

            LightSlider(
                icon: "sun.max.fill",
                label: "Brightness",
                value: Binding(
                    get: { Double(visibleBrightness) },
                    set: { store.setBrightness(Int($0.rounded()), for: device) }
                ),
                range: brightnessRange,
                valueText: state.isOn ? "\(visibleBrightness)%" : "Off",
                disabled: !hasState || !state.isOn
            )

            LightSlider(
                icon: "thermometer.sun.fill",
                label: "Warmth",
                value: Binding(
                    get: { Double(state.temperature) },
                    set: { store.setTemperature(Int($0.rounded()), for: device) }
                ),
                range: Double(KeyLightLimits.temperature.lowerBound)...Double(KeyLightLimits.temperature.upperBound),
                valueText: "\(state.temperature) K",
                disabled: !hasState
            )
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.orange.opacity(0.55), .white.opacity(0.5), .blue.opacity(0.55)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 2)
                .padding(.leading, 30)
                .padding(.trailing, 54)
                .allowsHitTesting(false)
            }

            if let error = store.errors[device.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(device.name)
    }
}

private struct LightSlider: View {
    let icon: String
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String
    let disabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)

            Slider(value: $value, in: range)
                .controlSize(.small)
                .disabled(disabled)
                .accessibilityLabel(label)
                .accessibilityValue(valueText)

            Text(valueText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .frame(height: 22)
        .opacity(disabled ? 0.55 : 1)
    }
}

private struct EmergencyLightButton: View {
    let isLightsOff: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let tint = isLightsOff ? Color.green : Color.red
        let title = isLightsOff ? "Lights On" : "Lights Off"
        let helper = isLightsOff ? "restore all" : "stop all"
        let systemImage = isLightsOff ? "lightbulb.2.fill" : "lightbulb.slash.fill"

        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
                Text(helper)
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.82)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(isHovering ? 1 : 0.88))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isLightsOff ? "Turn all Key Lights back on and restore the Borders ring light" : "Turn all lights off, including the Borders ring light")
        .accessibilityLabel(isLightsOff ? "Turn all lights on" : "Turn all lights off")
    }
}

private struct PairingInstructions: View {
    @ObservedObject var store: KeyLightStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pair or re-pair a Key Light", systemImage: "wifi")
                .font(.system(size: 14, weight: .semibold))

            Text("The app does not change Wi-Fi for you. To initialise or reinitialise the light:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("1. Power on the Key Light Air. Hold the rear reset button next to the power cord for 10 seconds until it flashes three times.\n2. Release the button, power the light off, wait 10 seconds, then power it back on.\n3. In Wi-Fi settings, choose the temporary “Key Light XXXX” network.\n4. Open the light’s local setup page and select your home Wi-Fi.")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Open Wi-Fi Settings", action: store.openWiFiSettings)
                Button("Open Pairing Page", action: store.openPairingPage)
                    .disabled(store.isSearching)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text("After joining the home network, come back here and press refresh. Repeating this flow is safe after a reinstall or on another Mac.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
