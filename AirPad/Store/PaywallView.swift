//
//  PaywallView.swift
//  AirPad
//
//  The AirPad Pro unlock screen, plus the reusable trial banner shown on the
//  main screen while the 7-day trial is running.
//

import SwiftUI

struct PaywallView: View {
    @ObservedObject private var store = ProStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 24)

                Text("AirPad Pro")
                    .font(.largeTitle.bold())

                Text("No ads. No subscription.\nOne price, yours forever.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    featureRow("dot.circle.and.hand.point.up.left.fill", "Air Mouse", "Point with your phone like a Wii remote")
                    featureRow("hand.point.up.left", "Hand Mouse", "Camera hand-tracking with gestures")
                    featureRow("playpause.fill", "Media & Presentation Remote", "Volume, playback, slides, brightness, lock")
                    featureRow("mic.fill", "Dictation", "Speak on the phone, type on the Mac")
                    featureRow("display", "Live Screen & Apps", "See and drive your Mac's screen")
                    featureRow("laptopcomputer.and.iphone", "Multi-Mac", "Pair and switch between all your Macs")
                    featureRow("hand.draw", "All future gestures", "Includes the upcoming gesture recorder")
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                if store.inTrial && !store.purchased {
                    Text("Free trial: \(store.trialDaysLeft) day\(store.trialDaysLeft == 1 ? "" : "s") left — everything is unlocked while you decide.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    busy = true
                    Task {
                        await store.purchase()
                        busy = false
                        if store.purchased { dismiss() }
                    }
                } label: {
                    Group {
                        if store.purchased {
                            Label("Unlocked — thank you!", systemImage: "checkmark.seal.fill")
                        } else if busy {
                            ProgressView()
                        } else {
                            Text("Unlock Pro — \(store.product?.displayPrice ?? "$7.99")")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || store.purchased)
                .padding(.horizontal)

                Button("Restore Purchase") {
                    Task { await store.restore() }
                }
                .font(.footnote)

                if let error = store.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Text("Trackpad, keyboard, and your first Mac are free forever.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 24)
            }
        }
        .navigationTitle("AirPad Pro")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func featureRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 30)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Small banner shown on the main screen during the trial.
struct TrialBanner: View {
    @ObservedObject private var store = ProStore.shared

    var body: some View {
        if store.inTrial && !store.purchased {
            NavigationLink(destination: PaywallView()) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.checkmark")
                    Text("Pro trial — \(store.trialDaysLeft) day\(store.trialDaysLeft == 1 ? "" : "s") left")
                        .font(.footnote.weight(.medium))
                    Spacer()
                    Text("Unlock")
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
    }
}

#Preview {
    NavigationStack { PaywallView() }
}
