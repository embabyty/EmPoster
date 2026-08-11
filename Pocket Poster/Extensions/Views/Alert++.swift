//
//  Alert++.swift
//  Cowabunga
//
//  Created by sourcelocation on 30/01/2023.
//

import UIKit

// credit: sourcelocation & TrollTools
var currentUIAlertController: UIAlertController?
var lastDismissTitle: String?


fileprivate let errorString = NSLocalizedString("Error", comment: "")
fileprivate let okString = NSLocalizedString("OK", comment: "")
fileprivate let cancelString = NSLocalizedString("Cancel", comment: "")

extension UIApplication {
    
    func dismissAlert(animated: Bool, completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            lastDismissTitle = currentUIAlertController?.title
            if let alert = currentUIAlertController {
                // Always clear pointer first so a follow-up present() won't chain on a dying VC
                currentUIAlertController = nil
                alert.dismiss(animated: animated) {
                    completion?()
                }
            } else {
                // Also dismiss any orphaned presented alert
                if let top = Self.topViewController(), top is UIAlertController {
                    top.dismiss(animated: animated) {
                        completion?()
                    }
                } else {
                    completion?()
                }
            }
        }
    }
    
    func alert(title: String = errorString, body: String, animated: Bool = true, withButton: Bool = true) {
        // Dismiss any existing alert first so we never stack a buttonless spinner under a new sheet
        dismissAlert(animated: false) {
            DispatchQueue.main.async {
                var body = body
                
                if title == errorString {
                    // append debug info
                    let device = UIDevice.current
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                    let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
                    let systemVersion = device.systemVersion
                    body += "\n\(device.systemName) \(systemVersion), v\(appVersion) build \(appBuild)"
                }
                
                let controller = UIAlertController(title: title, message: body, preferredStyle: .alert)
                // Always allow dismiss for non-progress alerts; progress uses withButton: false intentionally
                if withButton {
                    controller.addAction(.init(title: okString, style: .cancel))
                }
                currentUIAlertController = controller
                self.present(alert: controller)
            }
        }
    }
    
    func confirmAlert(title: String = errorString, body: String, confirmTitle: String = okString, onOK: @escaping () -> (), noCancel: Bool) {
        dismissAlert(animated: false) {
            DispatchQueue.main.async {
                let controller = UIAlertController(title: title, message: body, preferredStyle: .alert)
                if !noCancel {
                    controller.addAction(.init(title: cancelString, style: .cancel))
                }
                controller.addAction(.init(title: confirmTitle, style: noCancel ? .cancel : .default, handler: { _ in
                    onOK()
                }))
                currentUIAlertController = controller
                self.present(alert: controller)
            }
        }
    }
    
    func change(title: String = errorString, body: String) {
        DispatchQueue.main.async {
            currentUIAlertController?.title = title
            currentUIAlertController?.message = body
        }
    }
    
    /// Top-most VC in the key window (skips being-dismissed alerts when possible).
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? scenes.first?.windows.first
        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            // Prefer not to stop on a controller that is mid-dismiss
            if presented.isBeingDismissed { break }
            top = presented
        }
        return top
    }
    
    func present(alert: UIAlertController) {
        guard let topController = Self.topViewController() else { return }
        // If top is already an alert being shown, replace it
        if let existing = topController as? UIAlertController {
            existing.dismiss(animated: false) {
                Self.topViewController()?.present(alert, animated: true)
            }
            return
        }
        topController.present(alert, animated: true)
    }
}
