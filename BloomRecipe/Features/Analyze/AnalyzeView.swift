import SwiftUI

struct AnalyzeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            if let image = model.frontImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, BloomTheme.espresso.opacity(0.55)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }
            }

            VStack(spacing: 10) {
                ProgressView()
                    .tint(BloomTheme.roast)
                Text("Reading the bag")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                Text("Looking for roast, process, origin, and tasting notes.")
                    .font(.subheadline)
                    .foregroundStyle(BloomTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding(20)
        .bloomBackground()
        .navigationTitle("Analyze")
        .navigationBarTitleDisplayMode(.inline)
    }
}
