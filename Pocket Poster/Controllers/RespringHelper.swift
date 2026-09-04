//
//  RespringHelper.swift
//  EmPoster
//
//  Mond-style instant respring (WebKit GPU crash @neonmodder123).
//  No VC present/dismiss chain — WKWebView on a top-level window, load immediately.
//

import Foundation
import UIKit
import WebKit
import ObjectiveC

enum RespringHelper {
    
    /// Keep the respring window alive until the process dies.
    private static var stickyWindow: UIWindow?
    private static var stickyWebView: WKWebView?
    
    /// Direct crash payload (inner document from Mond — no outer iframe delay).
    /// Credit: @neonmodder123 / Mond
    private static let crashHTML = """
    <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width"></head><body><script>
    (function(){
      var c=document.createElement('div');
      c.style.cssText='perspective:1px;perspective-origin:9999999% 9999999%;';
      document.body.appendChild(c);
      for(var i=0;i<500;i++){
        var d=document.createElement('div');
        d.style.cssText='position:absolute;width:100vw;height:100vh;backdrop-filter:blur(100px);-webkit-backdrop-filter:blur(100px);transform:translate3d(100000px,100000px,'+i+'px) rotateY(90deg);';
        c.appendChild(d);
      }
      setInterval(function(){
        try{navigator.share({title:'R',text:'R'.repeat(100000)});}catch(e){}
        try{crypto.getRandomValues(new Uint8Array(1024*1024*10));}catch(e){}
      },0);
    })();
    </script></body></html>
    """
    
    /// Instant full respring (Mond path). Safe under LiveContainer.
    static func respring() {
        #if targetEnvironment(simulator)
        print("respring skipped on simulator")
        return
        #else
        // Must be main thread for UIWindow / WKWebView
        if !Thread.isMainThread {
            DispatchQueue.main.async { fireNow() }
            return
        }
        fireNow()
        #endif
    }
    
    static func respringNow() { respring() }
    
    private static func fireNow() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        
        // 1) Kill any alerts instantly so nothing blocks rendering
        currentUIAlertController?.dismiss(animated: false)
        currentUIAlertController = nil
        
        // 2) Build WKWebView + load crash HTML BEFORE showing window (starts process ASAP)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        // Shared process pool warms slightly faster on repeat
        config.processPool = WKProcessPool()
        
        let webView = WKWebView(frame: UIScreen.main.bounds, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .black
        
        // Load payload immediately — don't wait for layout/appear
        webView.loadHTMLString(crashHTML, baseURL: URL(string: "about:blank"))
        stickyWebView = webView
        
        // 3) Slap it on a top-level window (no present animation, no host VC)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        
        let window: UIWindow
        if let scene {
            window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.windowLevel = .alert + 100
        window.backgroundColor = .black
        window.isHidden = false
        
        let host = UIViewController()
        host.view.backgroundColor = .black
        host.view.addSubview(webView)
        webView.frame = host.view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.rootViewController = host
        window.makeKeyAndVisible()
        stickyWindow = window
        
        // Force a layout pass so WebKit starts compositing now
        window.layoutIfNeeded()
        webView.setNeedsLayout()
        webView.layoutIfNeeded()
        
        // Re-load once more after attach (some LC builds only execute JS after in-hierarchy)
        webView.loadHTMLString(crashHTML, baseURL: nil)
        
        // 4) Outside LiveContainer, also hit XPC immediately (no delay)
        let inLC = ProcessInfo.processInfo.environment["LC_HOME_PATH"] != nil
            || Bundle.main.bundlePath.contains("LiveContainer")
        if !inLC {
            restartFrontboard()
            restartBackboard()
        }
    }
}
