import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selectedFeed: Feed?

    var body: some View {
        List(selection: $selectedFeed) {
            Text("Feeds kommen hier hin")
        }
        .navigationTitle("Feedivo")
    }
}
