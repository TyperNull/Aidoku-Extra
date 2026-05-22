//
//  SceneDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/29/21.
//

import QuartzCore
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private static let bannerHeight: CGFloat = 30

    var window: UIWindow?
    private var incognitoBannerView: UIView?

    var totalBannerHeight: CGFloat {
        incognitoBannerView?.frame.height ?? 0
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = TabBarController()
            window.tintColor = .systemPink

            if UserDefaults.standard.bool(forKey: "General.useSystemAppearance") {
                window.overrideUserInterfaceStyle = .unspecified
            } else {
                if UserDefaults.standard.integer(forKey: "General.appearance") == 0 {
                    window.overrideUserInterfaceStyle = .light
                } else {
                    window.overrideUserInterfaceStyle = .dark
                }
            }

            self.window = window
            window.makeKeyAndVisible()
            AppRefreshRateController.shared.register()

            let incognitoBannerView = IncognitoBannerView()
            self.incognitoBannerView = incognitoBannerView
            incognitoBannerView.translatesAutoresizingMaskIntoConstraints = false
            window.insertSubview(incognitoBannerView, at: 0)

            NSLayoutConstraint.activate([
                incognitoBannerView.leadingAnchor.constraint(equalTo: window.leadingAnchor),
                incognitoBannerView.trailingAnchor.constraint(equalTo: window.trailingAnchor),
                incognitoBannerView.topAnchor.constraint(equalTo: window.topAnchor),
                incognitoBannerView.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: Self.bannerHeight)
            ])
        }

        if
            let url = connectionOptions.urlContexts.first?.url,
            let delegate = UIApplication.shared.delegate as? AppDelegate
        {
            delegate.handleUrl(url: url)
        }
    }

    let contentHideView: UIView = {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .systemBackground
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }()

    func sceneWillEnterForeground(_ scene: UIScene) {
        contentHideView.removeFromSuperview()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        contentHideView.removeFromSuperview()
        AppRefreshRateController.shared.apply()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        AppRefreshRateController.shared.suspend()

        let incognitoEnabled = UserDefaults.standard.bool(forKey: "General.incognitoMode")
        if incognitoEnabled {
            (scene as? UIWindowScene)?.windows.first?.addSubview(contentHideView)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url, let delegate = UIApplication.shared.delegate as? AppDelegate {
            delegate.handleUrl(url: url)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        didUpdate previousCoordinateSpace: any UICoordinateSpace,
        interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
        traitCollection previousTraitCollection: UITraitCollection
    ) {
        let newOrientation = if #available(iOS 16.0, *) {
            windowScene.effectiveGeometry.interfaceOrientation
        } else {
            windowScene.interfaceOrientation
        }
        guard newOrientation != previousInterfaceOrientation else { return }
        NotificationCenter.default.post(name: .orientationDidChange, object: newOrientation)
    }
}

enum AppRefreshRateMode: String, CaseIterable {
    case automatic = "auto"
    case sixtyHertz = "60"
    case oneTwentyHertz = "120"

    static let key = "General.refreshRate"

    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .automatic
    }

    static var isSupported: Bool {
        !ProcessInfo.processInfo.isMacCatalystApp && UIScreen.main.maximumFramesPerSecond > 60
    }

    static var titles: [String] {
        [
            NSLocalizedString("AUTOMATIC"),
            "60 Hz",
            "120 Hz"
        ]
    }

    func targetRefreshRate(maximumFramesPerSecond: Int) -> Int? {
        switch self {
            case .automatic:
                nil
            case .sixtyHertz:
                min(60, maximumFramesPerSecond)
            case .oneTwentyHertz:
                min(120, maximumFramesPerSecond)
        }
    }
}

final class AppRefreshRateController: NSObject {
    static let shared = AppRefreshRateController()

    private var displayLink: CADisplayLink?
    private var observers: [NSObjectProtocol] = []
    private var isRegistered = false

    func register() {
        guard !isRegistered else { return }
        isRegistered = true

        let notificationCenter = NotificationCenter.default
        observers.append(notificationCenter.addObserver(
            forName: Notification.Name(AppRefreshRateMode.key),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.apply()
        })
        observers.append(notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.apply()
        })
        observers.append(notificationCenter.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.suspend()
        })

        apply()
    }

    func apply() {
        guard
            AppRefreshRateMode.isSupported,
            UIApplication.shared.applicationState != .background,
            let targetRefreshRate = AppRefreshRateMode.current.targetRefreshRate(
                maximumFramesPerSecond: UIScreen.main.maximumFramesPerSecond
            )
        else {
            suspend()
            return
        }

        let displayLink = self.displayLink ?? CADisplayLink(
            target: self,
            selector: #selector(displayLinkDidUpdate(_:))
        )
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(targetRefreshRate),
            maximum: Float(targetRefreshRate),
            preferred: Float(targetRefreshRate)
        )

        if self.displayLink == nil {
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }
        displayLink.isPaused = false
    }

    func suspend() {
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @objc private func displayLinkDidUpdate(_ displayLink: CADisplayLink) {}
}
