//
//  InAppToastBanner.swift
//  Venture Local
//
//  Short top-leading banners for badge, level-up, and friend-request alerts.
//

import Combine
import SwiftUI

extension Notification.Name {
    static let ventureLocalInAppToast = Notification.Name("VentureLocalInAppToast")
}

enum InAppToastNotification {
    static func post(kind: ToastPayload.Kind, title: String, subtitle: String?) {
        var info: [String: Any] = ["toastKind": kind.rawValue, "title": title]
        if let subtitle { info["subtitle"] = subtitle }
        NotificationCenter.default.post(name: .ventureLocalInAppToast, object: nil, userInfo: info)
    }
}

struct ToastPayload {
    enum Kind: String {
        case badge
        case levelUp
        case friend
    }

    let kind: Kind
    let title: String
    let subtitle: String?

    init?(userInfo: [AnyHashable: Any]?) {
        guard
            let raw = userInfo?["toastKind"] as? String,
            let kind = Kind(rawValue: raw),
            let title = userInfo?["title"] as? String
        else { return nil }
        self.kind = kind
        self.title = title
        self.subtitle = userInfo?["subtitle"] as? String
    }
}

@MainActor
final class InAppToastController: ObservableObject {
    struct Toast: Identifiable {
        let id = UUID()
        let kind: ToastPayload.Kind
        let title: String
        let subtitle: String?
    }

    @Published private(set) var active: Toast?
    private var queue: [Toast] = []
    private var dismissWorkItem: DispatchWorkItem?

    func present(_ toast: Toast) {
        if active != nil {
            queue.append(toast)
            return
        }
        showNow(toast)
    }

    private func showNow(_ toast: Toast) {
        dismissWorkItem?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            active = toast
        }
        let item = DispatchWorkItem { [weak self] in
            self?.finishCurrentAndShowNext()
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: item)
    }

    private func finishCurrentAndShowNext() {
        withAnimation(.easeInOut(duration: 0.32)) {
            active = nil
        }
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.showNow(next)
        }
    }

    func consume(userInfo: [AnyHashable: Any]?) {
        guard let p = ToastPayload(userInfo: userInfo) else { return }
        present(Toast(kind: p.kind, title: p.title, subtitle: p.subtitle))
    }
}

struct InAppToastBannerView: View {
    let toast: InAppToastController.Toast
    @ObservedObject private var theme = ThemeSettings.shared

    var body: some View {
        let _ = theme.useDarkVintagePalette
        return HStack(alignment: .center, spacing: 10) {
            Text("NEW")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(VLColor.cream)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(VLColor.burgundy)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(VLColor.darkTeal)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.vlBody(14).weight(.semibold))
                    .foregroundStyle(VLColor.ink)
                    .lineLimit(2)
                if let sub = toast.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.vlCaption(11))
                        .foregroundStyle(VLColor.dustyBlue)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: 300, alignment: .leading)
        .background(VLColor.paperSurface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(VLColor.burgundy.opacity(0.35), lineWidth: 1.5))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(theme.useDarkVintagePalette ? 0.45 : 0.18), radius: 12, y: 4)
    }

    private var iconName: String {
        switch toast.kind {
        case .badge: return "rosette"
        case .levelUp: return "arrow.up.circle.fill"
        case .friend: return "person.2.fill"
        }
    }

    private var headline: String {
        switch toast.kind {
        case .badge: return toast.title
        case .levelUp: return toast.title.isEmpty ? "Lvl up" : "Lvl up · \(toast.title)"
        case .friend: return toast.title
        }
    }
}
