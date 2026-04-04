//
//  MoveView.swift
//  PTApp
//

import AudioToolbox
import SwiftUI

struct MoveView: View {
    @StateObject private var camera = CameraManager()
    @AppStorage("stride_audio_feedback") private var audioFeedback = true
    @State private var selectedExerciseIndex = 0
    @State private var targetReps = 15
    @State private var repCount = 0
    @State private var ghostMode = false
    @State private var showSessionSummary = false
    @State private var sessionActive = false
    @State private var formAverage: Double = 0.94
    @State private var compensations = 3

    private let exercises = [
        "Glute Bridge",
        "Clamshells",
        "Mini Squat to Box",
        "Single-Leg Bridge",
    ]

    private let targetMuscle = "Glutes"

    var body: some View {
        NavigationStack {
            ZStack {
                cameraLayer

                skeletonOverlay

                VStack(spacing: 0) {
                    topBar

                    HStack(alignment: .top) {
                        Spacer(minLength: 0)
                        repCounter
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 8)

                    Spacer(minLength: 0)

                    ScrollView(.vertical, showsIndicators: false) {
                        bottomControls
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                if !camera.isAuthorized {
                    permissionPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                camera.checkAuthorization()
            }
            .onDisappear {
                camera.stopRunning()
            }
            .onChange(of: camera.flashOn) { _, _ in
                camera.applyTorch()
            }
            .sheet(isPresented: $showSessionSummary) {
                SessionSummarySheet(
                    totalReps: repCount,
                    targetReps: targetReps,
                    formAverage: formAverage,
                    compensations: compensations,
                    onSave: { showSessionSummary = false },
                    onRetry: {
                        showSessionSummary = false
                        repCount = 0
                    },
                    onShare: { showSessionSummary = false }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var cameraLayer: some View {
        ZStack {
            if camera.isAuthorized {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [Color.black.opacity(0.85), Color.gray.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var skeletonOverlay: some View {
        GeometryReader { geo in
            SkeletonOverlayView(size: geo.size, ghostMode: ghostMode)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Button {
                camera.flashOn.toggle()
            } label: {
                Image(systemName: camera.flashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            Text("Target: \(targetMuscle)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.35), in: Capsule())

            Spacer()

            Button {
                camera.flipCamera()
            } label: {
                Image(systemName: "camera.rotate")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.top, 52)
    }

    private var repCounter: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 14)
                .frame(width: 160, height: 160)

            Circle()
                .trim(from: 0, to: CGFloat(min(Double(repCount) / Double(max(targetReps, 1)), 1)))
                .stroke(StrideTheme.success, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(-90))

            Text("\(repCount)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(radius: 4)
        }
        .contentShape(Circle())
        .onTapGesture {
            guard sessionActive else { return }
            registerRep(good: true)
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                ghostMode.toggle()
            } label: {
                Image(systemName: ghostMode ? "figure.walk.motion" : "figure.walk")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .offset(x: 8, y: 8)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {
            Text("Set phone 6 feet away, full body visible")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.35), in: Capsule())

            Picker("Exercise", selection: $selectedExerciseIndex) {
                ForEach(exercises.indices, id: \.self) { i in
                    Text(exercises[i]).tag(i)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 100)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Target reps")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(targetReps)")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                }
                Slider(value: Binding(
                    get: { Double(targetReps) },
                    set: { targetReps = Int($0) }
                ), in: 5...40, step: 1)
                .tint(StrideTheme.accent)
            }
            .padding(12)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 12) {
                Button {
                    sessionActive.toggle()
                    if sessionActive {
                        camera.startRunningIfNeeded()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } else {
                        showSessionSummary = true
                    }
                } label: {
                    Label(sessionActive ? "End session" : "Start session", systemImage: sessionActive ? "stop.fill" : "record.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(sessionActive ? .red : StrideTheme.accent)

                Button {
                    simulateCompensation()
                } label: {
                    Label("Test cue", systemImage: "waveform")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(.bottom, 12)
    }

    private var permissionPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.white)
            Text("Camera access is needed for Move.")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Enable it in Settings to use live form tracking.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding()
    }

    private func registerRep(good: Bool) {
        repCount += 1
        playFeedback(good: good)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if repCount >= targetReps {
            sessionActive = false
            showSessionSummary = true
        }
    }

    private func simulateCompensation() {
        playFeedback(good: false)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    private func playFeedback(good: Bool) {
        guard audioFeedback else { return }
        if good {
            AudioServicesPlaySystemSound(1057)
        } else {
            AudioServicesPlaySystemSound(1521)
        }
    }
}

private struct SkeletonOverlayView: View {
    let size: CGSize
    var ghostMode: Bool

    var body: some View {
        Canvas { context, _ in
            let joints = jointPositions(in: size)
            var path = Path()
            for pair in connections() {
                path.move(to: joints[pair.0])
                path.addLine(to: joints[pair.1])
            }
            context.stroke(
                path,
                with: .color(Color.green.opacity(ghostMode ? 0.35 : 0.85)),
                lineWidth: 3
            )
            for (_, point) in joints.enumerated() {
                let circle = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
                context.fill(
                    Path(ellipseIn: circle),
                    with: .color(Color.green.opacity(ghostMode ? 0.4 : 0.95))
                )
            }
        }
    }

    private func connections() -> [(Int, Int)] {
        [
            (0, 1), (1, 2), (1, 3), (2, 4), (3, 5),
            (1, 6), (6, 7), (6, 8), (7, 9), (8, 10),
        ]
    }

    private func jointPositions(in size: CGSize) -> [CGPoint] {
        let w = size.width
        let h = size.height
        let cx = w * 0.5
        return [
            CGPoint(x: cx, y: h * 0.12),
            CGPoint(x: cx, y: h * 0.20),
            CGPoint(x: cx - w * 0.10, y: h * 0.26),
            CGPoint(x: cx + w * 0.10, y: h * 0.26),
            CGPoint(x: cx - w * 0.14, y: h * 0.40),
            CGPoint(x: cx + w * 0.14, y: h * 0.40),
            CGPoint(x: cx, y: h * 0.38),
            CGPoint(x: cx - w * 0.08, y: h * 0.52),
            CGPoint(x: cx + w * 0.08, y: h * 0.52),
            CGPoint(x: cx - w * 0.10, y: h * 0.72),
            CGPoint(x: cx + w * 0.10, y: h * 0.72),
        ]
    }
}

private struct SessionSummarySheet: View {
    let totalReps: Int
    let targetReps: Int
    let formAverage: Double
    let compensations: Int
    let onSave: () -> Void
    let onRetry: () -> Void
    let onShare: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryRow(title: "Total reps", value: "\(totalReps)/\(targetReps)")
                    summaryRow(title: "Form average", value: "\(Int(formAverage * 100))%")
                    summaryRow(title: "Compensations detected", value: "\(compensations) (hip hike)")

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(height: 140)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "play.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(StrideTheme.accent)
                                Text("Watch your best rep")
                                    .font(.headline)
                            }
                        }

                    VStack(spacing: 10) {
                        Button("Save", action: onSave)
                            .buttonStyle(.borderedProminent)
                            .tint(StrideTheme.accent)
                            .frame(maxWidth: .infinity)

                        Button("Retry weak sets", action: onRetry)
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)

                        Button("Share with PT", action: onShare)
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .navigationTitle("Session complete")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
