import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Камера системы. `PhotosPicker` снимать не умеет, а снять бумажный документ
/// на телефон — первое, что человек с ним делает: сканера у него нет.
struct CameraPicker: UIViewControllerRepresentable {
    /// Готовый снимок. `nil` — человек закрыл камеру, не сняв.
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Есть ли у устройства камера. На симуляторе её нет, и кнопка, которая
    /// ничего не открывает, хуже, чем её отсутствие.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
