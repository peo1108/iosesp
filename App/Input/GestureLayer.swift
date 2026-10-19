import SwiftUI
import UIKit

/// Transparent touch layer: 3-finger double tap toggles the menu, 3-finger hold toggles recording,
/// a 1-finger tap reports its location and the layer's size (shooting, closing the menu).
struct GestureLayer: UIViewRepresentable {
    var onToggleMenu: () -> Void
    var onToggleRecording: () -> Void
    var onTap: (CGPoint, CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let c = context.coordinator

        let menu = UITapGestureRecognizer(target: c, action: #selector(Coordinator.menu))
        menu.numberOfTouchesRequired = 3
        menu.numberOfTapsRequired = 2

        let record = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.record(_:)))
        record.numberOfTouchesRequired = 3
        record.minimumPressDuration = 0.8

        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        tap.numberOfTouchesRequired = 1
        tap.numberOfTapsRequired = 1

        for recognizer in [menu, record, tap] {
            recognizer.delegate = c
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: GestureLayer

        init(parent: GestureLayer) {
            self.parent = parent
        }

        @objc func menu() {
            parent.onToggleMenu()
        }

        @objc func record(_ recognizer: UILongPressGestureRecognizer) {
            if recognizer.state == .began { parent.onToggleRecording() }
        }

        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            parent.onTap(recognizer.location(in: recognizer.view), recognizer.view?.bounds.size ?? .zero)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
