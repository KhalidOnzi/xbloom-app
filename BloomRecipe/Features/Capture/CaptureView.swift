import PhotosUI
import SwiftUI
import UIKit

struct CaptureView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCamera = false
    @State private var cameraTarget: PhotoSlot = .front
    @State private var frontPicker: PhotosPickerItem?
    @State private var backPicker: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                HStack(alignment: .top, spacing: 14) {
                    photoSlot(
                        title: "Front",
                        subtitle: "Required",
                        image: model.frontImage,
                        picker: $frontPicker,
                        slot: .front
                    )
                    photoSlot(
                        title: "Back",
                        subtitle: "Notes help",
                        image: model.backImage,
                        picker: $backPicker,
                        slot: .back
                    )
                }
                Button {
                    Task { await model.analyzeBag() }
                } label: {
                    Label("Read the bag", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(BloomButtonStyle())
                .disabled(model.frontImage == nil || model.isAnalyzing)

                if let errorMessage = model.errorMessage, model.path.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(BloomTheme.clay)
                }
            }
            .padding(20)
        }
        .bloomBackground()
        .navigationTitle("BloomRecipe")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.frontImage != nil || model.backImage != nil {
                    Button("Reset") { model.resetSession() }
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(image: cameraBinding)
                .ignoresSafeArea()
        }
        .onChange(of: frontPicker) { _, item in
            Task { model.frontImage = await loadImage(item) }
        }
        .onChange(of: backPicker) { _, item in
            Task { model.backImage = await loadImage(item) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photograph the bag.")
                .font(.system(.largeTitle, design: .serif).weight(.semibold))
                .foregroundStyle(BloomTheme.ink)
            Text("We’ll read the label, build an Omni Dripper recipe, then create it in your xBloom app.")
                .font(.body)
                .foregroundStyle(BloomTheme.muted)
        }
    }

    private func photoSlot(
        title: String,
        subtitle: String,
        image: UIImage?,
        picker: Binding<PhotosPickerItem?>,
        slot: PhotoSlot
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(BloomTheme.foam)
                    .frame(height: 220)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(BloomTheme.espresso.opacity(0.08), lineWidth: 1)
                    }
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title)
                        Text(title)
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(BloomTheme.muted)
                    }
                    .foregroundStyle(BloomTheme.roast)
                }
            }
            HStack {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Camera") {
                        cameraTarget = slot
                        showingCamera = true
                    }
                }
                PhotosPicker(selection: picker, matching: .images) {
                    Text("Library")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BloomTheme.roast)
        }
        .frame(maxWidth: .infinity)
    }

    private var cameraBinding: Binding<UIImage?> {
        switch cameraTarget {
        case .front: Bindable(model).frontImage
        case .back: Bindable(model).backImage
        }
    }

    private func loadImage(_ item: PhotosPickerItem?) async -> UIImage? {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return UIImage(data: data)
    }
}

private enum PhotoSlot {
    case front
    case back
}
