"""Build the same-origin web client and precache its release assets for offline use."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "backend/TeacherAI.Api/wwwroot"
subprocess.run([
    "flutter", "build", "web", "--release", "--no-web-resources-cdn",
    "--dart-define=TEACHER_CLOUD=true", f"--output={OUTPUT}",
], cwd=ROOT, check=True)

index = OUTPUT / "index.html"
registration = """<script>
if ('serviceWorker' in navigator) navigator.serviceWorker.register('/classroom-worker.js');
</script>"""
index.write_text(index.read_text().replace("</body>", registration + "\n</body>"))
assets = {}
for path in sorted(OUTPUT.rglob("*")):
    if path.is_file() and not path.name.startswith(".") and path.name != "classroom-worker.js":
        assets["/" + path.relative_to(OUTPUT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
version = hashlib.sha256(json.dumps(assets).encode()).hexdigest()[:16]
(OUTPUT / "classroom-worker.js").write_text(
    f"const version = 'teacher-shell-{version}';\n"
    f"const paths = new Set({json.dumps(list(assets))});\n" + """
self.addEventListener('install', event => {
  event.waitUntil(caches.open(version).then(cache => cache.addAll([...paths])));
});
self.addEventListener('activate', event => {
  event.waitUntil(Promise.all([
    clients.claim(),
    caches.keys().then(keys => Promise.all(keys.filter(
      key => key.startsWith('teacher-shell-') && key !== version
    ).map(key => caches.delete(key))))
  ]));
});
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (url.origin !== location.origin || event.request.method !== 'GET') return;
  const path = url.pathname === '/' ? '/index.html' : url.pathname;
  if (paths.has(path)) {
    event.respondWith(caches.open(version).then(async cache =>
      (await cache.match(path)) || fetch(event.request)));
  }
});
""")
