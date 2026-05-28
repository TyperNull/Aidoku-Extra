//
//  WasmNetWebViewHandler.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/12/23.
//

import WebKit

class WasmNetWebViewHandler: NSObject, WKNavigationDelegate, PopupWebViewHandler {

    var netModule: WasmNet
    var request: URLRequest

    lazy var webView: WKWebView = {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = self
        webView.customUserAgent = request.value(forHTTPHeaderField: "User-Agent")
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }()

#if !os(macOS)
    var popup: WebViewViewController?
#endif

    var done = false

    var popupShown: Bool {
#if !os(macOS)
        popup?.presentingViewController != nil
#else
        false
#endif
    }

    init(netModule: WasmNet, request: URLRequest) {
        self.netModule = netModule
        self.request = request
    }

    func load() {
#if os(macOS)
        let view = NSApplication.shared.windows.first?.contentView
#else
        let view = (UIApplication.shared.delegate as? AppDelegate)?.visibleViewController?.view
#endif
        guard let view = view else {
            netModule.semaphore.signal()
            return
        }
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalToConstant: 0),
            webView.heightAnchor.constraint(equalToConstant: 0),
            webView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            webView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        Task { @MainActor in
            if let url = self.request.url {
                await CloudflareCookieStore.injectCookies(into: self.webView, for: url)
            }
            self.webView.load(self.request)
            self.perform(#selector(self.timeout), with: nil, afterDelay: 12)
        }
    }

    func openWebViewPopup() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        webView.removeFromSuperview()

#if os(macOS)
        // todo
        timeout()
        return
#else
        popup?.dismiss(animated: true)
        popup = WebViewViewController(request: request, handler: self)
        popup!.view.addSubview(webView)
        webView.navigationDelegate = popup

        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalTo: popup!.view.widthAnchor),
            webView.heightAnchor.constraint(equalTo: popup!.view.heightAnchor),
            webView.centerXAnchor.constraint(equalTo: popup!.view.centerXAnchor),
            webView.centerYAnchor.constraint(equalTo: popup!.view.centerYAnchor)
        ])

        let vc = (UIApplication.shared.delegate as? AppDelegate)?.visibleViewController
        vc?.present(popup!, animated: true)
#endif
    }

    @objc func timeout() {
        if !done {
            done = true
            webView.removeFromSuperview()
            netModule.semaphore.signal()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigated(webView: webView, for: request)
    }

    func navigated(webView: WKWebView, for request: URLRequest) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { webViewCookies in
            guard let url = self.request.url else { return }

            // delay captcha check by 3s (so it loads in)
#if !os(macOS)
            if self.popup == nil, !CloudflareCookieStore.hasValidClearance(for: url) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.checkForCaptcha()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    self.checkForCaptcha()
                }
            }
#endif

            guard CloudflareCookieStore.foundClearance(in: webViewCookies, for: url) != nil else {
                return
            }

            webView.removeFromSuperview()
            self.done = true
#if !os(macOS)
            self.popup?.dismiss(animated: true)
#endif

            CloudflareCookieStore.saveCookies(from: webViewCookies, for: url)
            if let cookies = HTTPCookie.requestHeaderFields(with: webViewCookies)["Cookie"] {
                self.request.addValue(cookies, forHTTPHeaderField: "Cookie")
            }

            // re-send request
            URLSession.shared.dataTask(with: self.request) { data, response, error in
                self.netModule.storedResponse = WasmResponseObject(data: data, response: response, error: error)
                self.netModule.incrementRequest()
                self.netModule.semaphore.signal()
            }.resume()
        }
    }

    func canceled(request: URLRequest) {
        // if user dismissed the view without it succeeding
        if !done {
            webView.removeFromSuperview()
            netModule.semaphore.signal()
        }
    }

    @MainActor
    func checkForCaptcha() {
        guard !done, !popupShown else { return }
        if let url = request.url, CloudflareCookieStore.hasValidClearance(for: url) {
            return
        }
        // check if captcha or verify button is shown
        webView.evaluateJavaScript("""
        document.querySelector('input[name="cf-turnstile-response"]') !== null
            || document.body.textContent.includes('Verify you are human by completing')
        """
        ) { html, _ in
            if html as? Int == 1 {
                if !self.popupShown {
                    self.openWebViewPopup()
                }
            }
        }
    }
}
