//
//  Server.swift
//  TV_app
//
//  Created by Francisca Moore on 27-10-26.
//

import Foundation
import Hummingbird

func startServer(_ tv: TVState) async {
    let router = Router()

    let appButtons = catalog
        .map { "<button onclick=\"go('\($0.id)')\">\($0.name)</button>" }
        .joined(separator: "\n")

    let html = """
    <!doctype html>
        <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                  body { font-family: -apple-system; background:#111; color:#fff; margin:0; padding:20px; }
                  button { width:100%; padding:24px; margin:8px 0; font-size:20px;
                           border:0; border-radius:14px; background:#2a2a2e; color:#fff; }
                  button:active { background:#444; }
                  .pad { display:grid; grid-template-columns:repeat(3,1fr); gap:8px; margin-top:16px; }
                  #touchpad { height:220px; margin-top:16px; border-radius:14px; background:#1c1c1e;
                  display:flex; align-items:center; justify-content:center; color:#666; touch-action:none; }
                  #kb { width:100%; box-sizing:border-box; padding:18px; margin-top:16px;
                          font-size:18px; border:0; border-radius:14px; background:#1c1c1e; color:#fff; }
                </style>
            </head>
            <body>
                <div class="pad">
                    <button onclick="fetch('/home')">🏠</button>
                    <button onclick="key('up')">▲</button>
                    <span></span>
                    <button onclick="key('left')">◀</button>
                    <button onclick="key('enter')">OK</button>
                    <button onclick="key('right')">▶</button>
                    <button onclick="key('back')">↩︎</button>
                    <button onclick="key('down')">▼</button>
                    <button onclick="key('space')">⏯</button>
                </div>
                    <div id="touchpad">trackpad</div>
                    <button onclick="document.getElementById('kb').focus()">⌨️ Teclado</button>
                    <input id="kb" type="text" placeholder="Write on TV…"
                           autocapitalize="off" autocorrect="off" autocomplete="off"
                           spellcheck="false" enterkeyhint="search"> \(appButtons)
                <script>
                  function go(name) { fetch('/open/' + name); }
                  function key(k) { fetch('/key/' + k);}
                    let last = null, moved = false, pending = false, ax = 0, ay = 0;
                    const pad = document.getElementById('touchpad');

                    pad.addEventListener('touchstart', e => { last = e.touches[0]; moved = false; });
                    pad.addEventListener('touchmove', e => {
                      e.preventDefault();
                      const t = e.touches[0];
                      ax += (t.clientX - last.clientX) * 2.5;
                      ay += (t.clientY - last.clientY) * 2.5;
                      last = t; moved = true;
                      if (!pending) {
                        pending = true;
                        setTimeout(() => {
                          fetch(`/move/${ax.toFixed(1)}/${ay.toFixed(1)}`);
                          ax = 0; ay = 0; pending = false;
                        }, 50);
                      }
                    }, { passive: false });
                    pad.addEventListener('touchend', () => { if (!moved) fetch('/click'); });   
                    let prev = '', queue = Promise.resolve();
                    const kb = document.getElementById('kb');

                    function sendText(del, text) {
                      queue = queue.then(() => fetch(`/type?del=${del}&t=${encodeURIComponent(text)}`));
                    }

                    kb.addEventListener('input', () => {
                      const now = kb.value;
                      let i = 0;
                      while (i < prev.length && i < now.length && prev[i] === now[i]) i++;
                      sendText(prev.length - i, now.slice(i));
                      prev = now;
                    });

                    kb.addEventListener('keydown', e => {
                      if (e.key === 'Enter') {
                        e.preventDefault();
                        queue = queue.then(() => fetch('/key/enter'));
                        kb.value = ''; prev = '';
                      }
                    });
                </script>
            </body>
        </html>
    """
    
    router.get("/") { _, _ -> Response in
        Response(
            status: .ok,
            headers: [.contentType: "text/html; charset=utf-8"],
            body: .init(byteBuffer: ByteBuffer(string: html))
        )
    }
    
    router.get("home") { _, _ -> HTTPResponse.Status in
        await tv.goHome()
        return .ok
    }
    
    router.get("open/:name") { _, context -> HTTPResponse.Status in
        let name = context.parameters.get("name") ?? ""
        await tv.open(name)
        return .ok
    }
    
    router.get("key/:name") { _, context -> HTTPResponse.Status in
        let name = context.parameters.get("name") ?? ""
        await tv.press(name)
        return .ok
    }
    
    router.get("move/:dx/:dy") { _, context -> HTTPResponse.Status in
        let dx = context.parameters.get("dx", as: Double.self) ?? 0
        let dy = context.parameters.get("dy", as: Double.self) ?? 0
        await tv.moveCursor(dx: dx, dy: dy)
        return .ok
    }

    router.get("click") { _, _ -> HTTPResponse.Status in
        await tv.click()
        return .ok
    }
    
    router.get("type") { request, _ -> HTTPResponse.Status in
        let text = request.uri.queryParameters.get("t") ?? ""
        let del = request.uri.queryParameters.get("del", as: Int.self) ?? 0
        await tv.type(text, deleting: del)
        return .ok
    }
    
    router.get("editing") { _, _ -> String in
        await tv.isEditing() ? "1" : "0"
    }

    let app = Application(
        router: router,
        configuration: .init(address: .hostname("0.0.0.0", port: 8080))
    )
    do {
        try await app.runService()
    } catch{
        print("Server error:", error)
    }
}
