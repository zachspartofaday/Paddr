import SwiftUI

struct KeyAssignment: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let selection: Binding<String>
}
