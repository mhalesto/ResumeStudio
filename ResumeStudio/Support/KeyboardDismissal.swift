import SwiftUI
import UIKit

enum AppKeyboard {
  @MainActor
  static func dismiss() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
  }
}

private struct KeyboardDismissalModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .scrollDismissesKeyboard(.interactively)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") {
            AppKeyboard.dismiss()
          }
          .fontWeight(.semibold)
        }
      }
  }
}

extension View {
  /// Gives every editable form the same predictable keyboard behaviour,
  /// including keyboards such as phone and number pads with no return key.
  func supportsKeyboardDismissal() -> some View {
    modifier(KeyboardDismissalModifier())
  }
}
