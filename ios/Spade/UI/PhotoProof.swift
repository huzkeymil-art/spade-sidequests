import PhotosUI
import SwiftUI
import UIKit

/// Shown when a child finishes a parent's quest that asks for a photo.
/// The quest only counts once a photo is chosen.
struct PhotoProofSheet: View {
    let title: String
    let parent: String
    /// Called with the chosen photo. The quest is then sealed.
    let use: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: UIImage?
    @State private var item: PhotosPickerItem?
    @State private var camera = false
    private let hasCamera = UIImagePickerController.isSourceTypeAvailable(.camera)

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Show \(parent)") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(parent) asked for a photo of this one:")
                        .font(Typeface.text())
                        .foregroundStyle(Ink.dim)
                    Text(title)
                        .font(Typeface.display(30))
                        .foregroundStyle(Ink.bone)
                        .fixedSize(horizontal: false, vertical: true)
                    Group {
                        if let picked {
                            Image(uiImage: picked)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 340)
                                .accessibilityLabel("The chosen photo")
                        } else {
                            Image(systemName: "camera")
                                .font(.system(size: 34, weight: .regular))
                                .foregroundStyle(Ink.faint)
                                .frame(maxWidth: .infinity, minHeight: 190)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(8)
                    .plate(fill: Ink.ink, edge: picked == nil ? Ink.moss2 : Ink.verdigris, notch: 8)
                    Text("It stays on your iPhone. It goes to \(parent) along with your message when you tap Send in Allowance.")
                        .font(Typeface.italic(15))
                        .foregroundStyle(Ink.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            VStack(spacing: 8) {
                if let picked {
                    Button("Use this photo") {
                        use(picked)
                        dismiss()
                    }
                    .buttonStyle(PlateButtonStyle(kind: .primary, block: true))
                }
                HStack(spacing: 8) {
                    if hasCamera {
                        Button(picked == nil ? "Take photo" : "Take another") {
                            Feedback.tap()
                            camera = true
                        }
                        .buttonStyle(PlateButtonStyle(kind: picked == nil ? .primary : .plain, block: true))
                    }
                    PhotosPicker(selection: $item, matching: .images) {
                        Text(picked == nil ? "Choose photo" : "Choose another")
                    }
                    .buttonStyle(PlateButtonStyle(kind: picked == nil && !hasCamera ? .primary : .plain, block: true))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .spadeSheet()
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in
                camera = false
                if let image { picked = image }
            }
            .ignoresSafeArea()
        }
        .onChange(of: item) { _, chosen in
            guard let chosen else { return }
            Task { @MainActor in
                if let data = try? await chosen.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    picked = image
                }
            }
        }
    }
}

/// The iPhone's own camera screen.
private struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(done: done)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void

        init(done: @escaping (UIImage?) -> Void) {
            self.done = done
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            done(nil)
        }
    }
}
