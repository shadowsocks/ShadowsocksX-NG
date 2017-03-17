//
//  TextInput.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 5/12/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

import Foundation

#if !RX_NO_MODULE
    import RxSwift
#endif

#if os(iOS) || os(tvOS)
    import UIKit

    /// Represents text input with reactive extensions.
    public struct TextInput<Base: UITextInput> {
        /// Base text input to extend.
        public let base: Base

        /// Reactive wrapper for `text` property.
        public let text: ControlProperty<String?>

        /// Initializes new text input.
        ///
        /// - parameter base: Base object.
        /// - parameter text: Textual control property.
        public init(base: Base, text: ControlProperty<String?>) {
            self.base = base
            self.text = text
        }
    }

    extension Reactive where Base: UITextField {
        /// Reactive text input.
        public var textInput: TextInput<Base> {
            return TextInput(base: base, text: self.text)
        }
    }

    extension Reactive where Base: UITextView {
        /// Reactive text input.
        public var textInput: TextInput<Base> {
            return TextInput(base: base, text: self.text)
        }
    }

#endif

#if os(macOS)
    import Cocoa

    /// Represents text input with reactive extensions.
    public struct TextInput<Base: NSTextInputClient> {
        /// Base text input to extend.
        public let base: Base

        /// Reactive wrapper for `text` property.
        public let text: ControlProperty<String?>

        /// Initializes new text input.
        ///
        /// - parameter base: Base object.
        /// - parameter text: Textual control property.
        public init(base: Base, text: ControlProperty<String?>) {
            self.base = base
            self.text = text
        }
    }

    extension Reactive where Base: NSTextField, Base: NSTextInputClient {
        /// Reactive text input.
        public var textInput: TextInput<Base> {
            return TextInput(base: base, text: self.text)
        }
    }

#endif


