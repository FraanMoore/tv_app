//
//  ContentView.swift
//  TV_app
//
//  Created by Francisca Moore on 27-10-26.
//

import SwiftUI
import WebKit

struct StreamingApp: Identifiable {
    let id: String
    let name: String
    let url: String
    let color: Color
}

let catalog: [StreamingApp] = [
    .init(id: "netflix", name: "Netflix", url: "https://www.netflix.com", color: .red),
    .init(id: "youtube", name: "YouTube", url: "https://www.youtube.com/tv", color: .pink),
    .init(id: "disney", name: "Disney+", url: "https://www.disneyplus.com", color: .blue),
    .init(id: "prime", name: "Prime Video", url: "https://www.primevideo.com", color: .cyan),
    .init(id: "appletv", name: "Apple TV", url: "https://tv.apple.com", color: .gray),
    .init(id: "crunchyroll", name: "Crunchyroll", url: "https://www.crunchyroll.com", color: .orange),
]

struct WebView: NSViewRepresentable {
    let url: URL
    let tv: TVState

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView()
        tv.webView = web
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        if web.url != url {
            let isYouTube = url.host?.contains("youtube") == true
            web.customUserAgent = isYouTube
                ? "Mozilla/5.0 (SMART-TV; Linux; Tizen 6.5) AppleWebKit/537.36 (KHTML, like Gecko) 85.0.4183.93/6.5 TV Safari/537.36"
                : nil
            web.load(URLRequest(url: url))
        }
    }
}

@MainActor
@Observable
class TVState {
    var current: URL? = nil
    var selected = 0
    @ObservationIgnored weak var webView: WKWebView?
    
    func open(_ name: String) {
        if let app = catalog.first(where: { $0.id == name }),
           let url = URL(string: app.url) {
            current = url
        }
    }

    func goHome() { current = nil }

    private func navigateHome(_ name: String) {
        let cols = 3, count = catalog.count
        switch name {
        case "left":  selected = max(selected - 1, 0)
        case "right": selected = min(selected + 1, count - 1)
        case "up":    if selected - cols >= 0 { selected -= cols }
        case "down":  if selected + cols < count { selected += cols }
        case "enter": open(catalog[selected].id)
        default: break
        }
    }
    
    private let keys: [String: (UInt16, String)] = [
        "up":   (126, String(UnicodeScalar(NSUpArrowFunctionKey)!)),
        "down": (125, String(UnicodeScalar(NSDownArrowFunctionKey)!)),
        "left": (123, String(UnicodeScalar(NSLeftArrowFunctionKey)!)),
        "right":(124, String(UnicodeScalar(NSRightArrowFunctionKey)!)),
        "enter":(36, "\r"),
        "space":(49, " "),
        "backspace": (51, "\u{7F}"),
    ]
    
    private func sendKey(_ code: UInt16, _ chars: String) {
        guard let web = webView else { return }
        web.window?.makeFirstResponder(web)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: web.window?.windowNumber ?? 0, context: nil,
                characters: chars, charactersIgnoringModifiers: chars,
                isARepeat: false, keyCode: code
            ) else { continue }
            type == .keyDown ? web.keyDown(with: event) : web.keyUp(with: event)
        }
    }

    func press(_ name: String) {
        if current == nil { navigateHome(name); return }
        if name == "back" { webView?.goBack(); return }
        guard let (code, chars) = keys[name] else { return }
        sendKey(code, chars)
    }

    func type(_ text: String, deleting: Int = 0) {
        for _ in 0..<deleting { press("backspace") }
        guard !text.isEmpty,
              let data = try? JSONEncoder().encode(text),
              let literal = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("document.execCommand('insertText', false, \(literal))")
    }
    var cursor = CGPoint(x: 400, y: 300)

    private func sendMouse(_ type: NSEvent.EventType) {
        guard let web = webView, let window = web.window else { return }
        let point = web.convert(cursor, to: nil)
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0
        ) else { return }
        window.sendEvent(event)
    }

    func moveCursor(dx: Double, dy: Double) {
        guard let web = webView else { return }
        web.window?.acceptsMouseMovedEvents = true
        cursor.x = min(max(cursor.x + dx, 0), web.bounds.width)
        cursor.y = min(max(cursor.y + dy, 0), web.bounds.height)
        sendMouse(.mouseMoved)
        web.evaluateJavaScript("""
        (function(){
          var c = document.getElementById('__cursor');
          if (!c) {
            c = document.createElement('div'); c.id = '__cursor';
            c.style.cssText = 'position:fixed;width:18px;height:18px;border-radius:50%;background:#fff;border:2px solid #000;z-index:2147483647;pointer-events:none;transform:translate(-50%,-50%)';
            document.body.appendChild(c);
          }
          c.style.left = '\(cursor.x)px'; c.style.top = '\(cursor.y)px';
        })()
        """)
    }

    func click() {
        sendMouse(.leftMouseDown)
        sendMouse(.leftMouseUp)
    }
    
    func isEditing() async -> Bool {
        guard let web = webView else { return false }
        let js = """
        (function(){
          var e = document.activeElement;
          return !!e && (e.tagName === 'INPUT' || e.tagName === 'TEXTAREA' || e.isContentEditable);
        })()
        """
        let result = try? await web.evaluateJavaScript(js)
        return (result as? Bool) ?? false
    }
}

struct HomeView: View {
    @Environment(TVState.self) private var tv

    var body: some View {
        VStack(spacing: 48) {
            Text("¿Qué quieres ver?")
                .font(.system(size: 48, weight: .semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 32), count: 3),
                      spacing: 32) {
                ForEach(Array(catalog.enumerated()), id: \.element.id) { index, app in
                    let focused = tv.selected == index
                    Text(app.name)
                        .font(.system(size: 32, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 150)
                        .background(app.color.opacity(0.85),
                                    in: RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24)
                            .stroke(.white, lineWidth: focused ? 6 : 0))
                        .scaleEffect(focused ? 1.06 : 1)
                        .animation(.easeOut(duration: 0.15), value: tv.selected)
                        .onTapGesture { tv.selected = index; tv.open(app.id) }
                }
            }
            .padding(.horizontal, 120)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .foregroundStyle(.white)
    }
}

struct ContentView: View {
    @Environment(TVState.self) private var tv

    var body: some View {
        Group {
            if let url = tv.current {
                WebView(url: url, tv: tv)
            } else {
                HomeView()
            }
        }
        .onAppear { NSApp.windows.first?.toggleFullScreen(nil) }
    }
}
