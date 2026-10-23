//
//  CustomTextField.swift
//
//
//  Created by Leon Böttger on 13.07.22.
//

import SwiftUI
import UIKit

public struct CustomTextField: View {
    @Binding private var text: String
    private let placeholder: String
    private let textAlignment: NSTextAlignment
    @State private var isFirstResponder = false
    public init(text: Binding<String>, placeholder: String, textAlignment: NSTextAlignment) {
        _text = text
        self.placeholder = placeholder.localized()
        self.textAlignment = textAlignment
    }

    public var body: some View {
        EnhancedTextField(
            text: $text, placeholder: placeholder, isFirstResponder: $isFirstResponder,
            textAlignment: textAlignment
        )
        .offset(x: -5, y: luiModel.textFieldOffset)
        .frame(height: luiModel.SettingsLabelHeight)
    }
}

private struct EnhancedTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var isFirstResponder: Bool
    let textAlignment: NSTextAlignment

    func makeUIView(context: Context) -> ModifiedTextField {
        let field = ModifiedTextField(frame: .zero)
        field.spellCheckingType = .no
        field.inputAccessoryView = UIView()
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.returnKeyType = .done
        field.autocorrectionType = .default
        field.keyboardType = .default
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let size = UIFont.preferredFont(forTextStyle: .body).pointSize
        if let descriptor = UIFont.systemFont(ofSize: size, weight: .regular).fontDescriptor.withDesign(
            .rounded
        ) {
            field.font = UIFont(descriptor: descriptor, size: size)
        } else {
            field.font = UIFont.preferredFont(forTextStyle: .body)
        }
        field.textColor = UIColor(.mainColor)
        field.textAlignment = textAlignment
        return field
    }

    func updateUIView(_ field: ModifiedTextField, context: Context) {
        field.text = text
        field.placeholder = placeholder
        DispatchQueue.main.async {
            if isFirstResponder, !context.coordinator.didBecomeFirstResponder {
                field.becomeFirstResponder()
                context.coordinator.didBecomeFirstResponder = true
            } else if !isFirstResponder, context.coordinator.didBecomeFirstResponder {
                field.resignFirstResponder()
                context.coordinator.didBecomeFirstResponder = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let parent: EnhancedTextField
        var didBecomeFirstResponder = false
        init(_ parent: EnhancedTextField) {
            self.parent = parent
        }

        func textFieldDidChangeSelection(_ field: UITextField) {
            DispatchQueue.main.async { self.parent.text = field.text ?? "" }
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            return true
        }

        func textFieldDidBeginEditing(_: UITextField) {
            DispatchQueue.main.async {
                self.didBecomeFirstResponder = true
                self.parent.isFirstResponder = true
            }
        }

        func textFieldDidEndEditing(_: UITextField) {
            DispatchQueue.main.async {
                self.didBecomeFirstResponder = false
                self.parent.isFirstResponder = false
            }
        }
    }
}

private final class ModifiedTextField: UITextField {
    private let padding = UIEdgeInsets(
        top: 0, left: 5, bottom: luiModel.BottomBarHeight * 1.5, right: 5
    )
    override func textRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: padding)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: padding)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: padding)
    }
}
