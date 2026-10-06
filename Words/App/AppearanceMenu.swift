import SwiftUI

/// The small button beside the sidebar toggle: how the application looks.
///
/// Not a Settings window. There is one preference in this app that is genuinely
/// a preference, and putting it behind ⌘, in a window with nothing else in it
/// would be a heavier promise than the app can keep.
struct AppearanceMenu: View {
    @Environment(AppSettings.self) private var settings

    @State private var isPresented = false

    var body: some View {
        @Bindable var settings = settings

        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .help("Appearance")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Appearance")
                    .font(.subheadline.weight(.semibold))

                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppSettings.Appearance.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(16)
            .frame(width: 240)
        }
    }
}
