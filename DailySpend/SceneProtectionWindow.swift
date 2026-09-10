import SwiftUI
import UIKit

/// Protects the entire scene, including sheets, file pickers and share panels.
/// A SwiftUI overlay on the tab bar alone sits *behind* presented controllers.
struct SceneProtectionWindow<Content: View>: UIViewRepresentable {
    let isPresented: Bool
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: AttachmentView, context: Context) {
        let coordinator = context.coordinator
        let content = AnyView(content())
        let isPresented = isPresented
        view.onWindowChange = { [weak view, weak coordinator] in
            coordinator?.update(host: view?.window, presented: isPresented, content: content)
        }
        coordinator.update(host: view.window, presented: isPresented, content: content)
    }

    static func dismantleUIView(_ view: AttachmentView, coordinator: Coordinator) {
        view.onWindowChange = nil
        coordinator.hide()
    }

    final class AttachmentView: UIView {
        nonisolated deinit { }
        var onWindowChange: (() -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange?()
        }
    }

    // Avoid an inferred actor-isolated deinitializer (the Swift 6.3 optimizer
    // and older iOS 26 runtimes both have failures in that generated path).
    // All window access is still explicitly confined to the main actor.
    nonisolated final class Coordinator {
        private var protectionWindow: UIWindow?
        private weak var hostWindow: UIWindow?

        @MainActor func update(host: UIWindow?, presented: Bool, content: AnyView) {
            guard presented else {
                hide()
                // The attachment can move/reappear after the protection
                // window was dismissed. Always restore the current host too.
                host?.accessibilityElementsHidden = false
                return
            }
            guard let host, let scene = host.windowScene else { return }
            if protectionWindow?.windowScene !== scene {
                hide()
                hostWindow = host
                let window = UIWindow(windowScene: scene)
                window.windowLevel = .alert + 1
                window.accessibilityViewIsModal = true
                protectionWindow = window
            }
            host.accessibilityElementsHidden = true
            if let controller = protectionWindow?.rootViewController as? UIHostingController<AnyView> {
                controller.rootView = content
            } else {
                protectionWindow?.rootViewController = UIHostingController(rootView: content)
            }
            protectionWindow?.rootViewController?.view.accessibilityViewIsModal = true
            if protectionWindow?.isHidden == true {
                host.endEditing(true)
                protectionWindow?.makeKeyAndVisible()
            }
        }

        @MainActor func hide() {
            let wasKey = protectionWindow?.isKeyWindow == true
            protectionWindow?.isHidden = true
            protectionWindow = nil
            hostWindow?.accessibilityElementsHidden = false
            if wasKey { hostWindow?.makeKey() }
        }
    }
}
