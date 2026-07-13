import SwiftUI

struct RootView: View {
  var body: some View {
    NavigationStack {
      HomeView()
    }
  }
}

#Preview {
  RootView()
    .environmentObject(ResumeStore(initialDocument: .example))
}
