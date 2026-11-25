#!/usr/bin/env bash
#
# Issue の作業の種類の検出器(`issue-flow-kind-violations.py`)が通す作成を、実物の bash と gh で走らせ、
# gh が実際に送った作成に flow:* か宣言の行が載っているかを確かめる判定表。
#
# 使い方: bash .claude/hooks/lib/issue-flow-kind-real-gh-cases.sh [検出器のパス]
# 出力が `ok` だけなら期待どおり。`NG` が 1 行でも出たら、検出器が通したのに実物は満たさない作成を送っている。
#
# **`issue-flow-kind-cases.sh` の期待は、書いた人が思い込んだ gh と bash の読み方で決まる。** 同じ思い込みで
# 検出器と表の両方を書くと表は緑のまま残り、`--input` があると `-f` がクエリに回る・`--body-file` が `--body`
# より勝つ・`--web=false` は作成する・標準入力は最後のリダイレクトで決まる、といった実物との食い違いは
# 移植元では外のレビューでしか見つからなかった(design-composer の `harness/records/pr-1431.md` の指摘 30〜35)。ここでは期待を書かず、
# 実物の送信を正解にする。
#
# 入力は `issue-flow-kind-cases.sh` の検出器の表(区切り `CASES` の最初のヒアドキュメント)の `bash` 形の行で、
# `miss` 以外のものを読む(表を写さないため、その書式に依存する)。各行をそのまま走らせるほか、
# 1 つの gh だけの行には、後ろに付け足すと送るものが変わる指定(`VARIANTS`)を 1 つずつ足して走らせる。
#
# 判定は片向きだけを見る: **検出器が pass なのに、実物が自リポジトリへ flow:* も宣言の行も無い作成を送ったら NG。**
# 逆向き(検出器が deny で、実物は満たす)は見ない。読めないものを止める・他リポジトリでも止める、といった
# 止めすぎは表が `deny` で意図して固定しているため。
#
# gh は `GH_HOST` を手元のダミーのサーバーに向け、そのサーバーが受けた REST と GraphQL の作成を記録する。
# github.com へ向かうもの(`-R github.com/…`)は届かない proxy へ送って落とす。gh と openssl が無いと NG にする
# (黙って 0 件で通さない。走らせる層は `.claude/hooks/README.md`「配線」のこの表の行)。
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

lib_dir="$(cd "$(dirname "$0")" && pwd)"
detector="${1:-$lib_dir/issue-flow-kind-violations.py}"
work="$(mktemp -d)"
trap 'rm -rf "$work" "$server_dir"' EXIT
server_dir="$(mktemp -d)"

source "$lib_dir/case-table.sh"
source "$lib_dir/issue-flow-kind-fixtures.sh"

# 自リポジトリの作成が満たしているかを判定し、`NG|ケース名|理由` か `ok|ケース名|-` を出す。
#
# 引数は検出器のパス・作業ディレクトリ・origin の URL・ダミーのサーバーの置き場。標準入力は `ケース名|入力` の
# 1 行 1 ケース。
replay_runner="$(cat <<'PY'
import http.server
import importlib.util
import json
import os
import ssl
import subprocess
import sys
import threading
import traceback

sys.dont_write_bytecode = True
detector_path, work, origin, server_dir = sys.argv[1:5]
spec = importlib.util.spec_from_file_location("issue_flow_kind_violations", detector_path)
detector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(detector)

OWN = "acme/widgets"
FLOW = "flow:"
# 1 つの gh だけの行の後ろに付け足す指定。gh が送るものを変える読み方を 1 つずつ足す。
VARIANTS = {
    "issue": (" --body-file @W/plain.md", " -b 本文だけ", " --web=false", " < @W/plain.md"),
    "api": (" --input @W/in-plain.json", " -f body=本文だけ"),
}
# ダミーのサーバーが持つラベル。gh issue create は名前を id に引けないと作成を送らない。
LABEL_NAMES = {"bug", "type:plan", "flow:", "flow:feature", "flow:bugfix", "flow:refactor", "flow:investigation"}
requests = []


def repository_id(owner, name):
    return f"R:{owner}/{name}".lower()


def graphql(query, variables):
    if "createIssue" in query:
        requests.append(("graphql", variables.get("input", {})))
        return {"createIssue": {"issue": {"id": "I1", "url": "https://localhost/i/1", "number": 1}}}
    if "labels" in query:
        nodes = [{"id": "L:" + n, "name": n} for n in sorted(LABEL_NAMES)]
        return {"repository": {"labels": {"nodes": nodes, "pageInfo": {"hasNextPage": False, "endCursor": ""}}}}
    owner, name = variables.get("owner", ""), variables.get("name", "")
    repo = {"id": repository_id(owner, name), "name": name, "owner": {"login": owner}}
    return {"repository": {**repo, "hasIssuesEnabled": True, "viewerPermission": "ADMIN"}}


class Handler(http.server.BaseHTTPRequestHandler):
    # 標準入力から読んだ本文(`--input -`)は content-length が無く chunked で届く。
    def read_body(self):
        if "chunked" not in (self.headers.get("transfer-encoding") or "").lower():
            return self.rfile.read(int(self.headers.get("content-length") or 0))
        chunks = []
        while (size := int(self.rfile.readline().split(b";")[0].strip() or b"0", 16)) > 0:
            chunks.append(self.rfile.read(size))
            self.rfile.readline()
        self.rfile.readline()
        return b"".join(chunks)

    def respond(self):
        raw = self.read_body().decode("utf-8", "replace")
        if self.path.endswith("/graphql"):
            payload = json.loads(raw)
            out = {"data": graphql(payload.get("query", ""), payload.get("variables") or {})}
        else:
            if self.command == "POST":
                requests.append(("rest", self.path.split("?")[0], raw))
            out = {"number": 1, "html_url": "https://localhost/i/1"}
        data = json.dumps(out).encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = do_POST = do_PATCH = respond

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
tls.load_cert_chain(os.path.join(server_dir, "cert.pem"), os.path.join(server_dir, "key.pem"))
server.socket = tls.wrap_socket(server.socket, server_side=True)
threading.Thread(target=server.serve_forever, daemon=True).start()
host = f"localhost:{server.server_address[1]}"
unreachable = "http://127.0.0.1:9"
gh_env = {
    **os.environ,
    "SSL_CERT_FILE": os.path.join(server_dir, "cert.pem"),
    "NO_PROXY": "localhost,127.0.0.1", "no_proxy": "localhost,127.0.0.1",
    "HTTPS_PROXY": unreachable, "https_proxy": unreachable, "HTTP_PROXY": unreachable, "http_proxy": unreachable,
    "GH_HOST": host, "GH_ENTERPRISE_TOKEN": "x", "GH_CONFIG_DIR": os.path.join(server_dir, "gh-config"),
    "GH_REPO": f"{host}/{OWN}", "GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1", "GH_BROWSER": "true",
    "GIT_CEILING_DIRECTORIES": os.path.dirname(work),
}
for name in ("GITHUB_TOKEN", "GH_TOKEN"):
    gh_env.pop(name, None)


def expand(text):
    return text.replace("⏎", "\n").replace("⇥", "\t").replace("¦", "|").replace("@W", work)


def detector_passes(command):
    os.chdir(os.path.join(work, "elsewhere"))
    data = {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": work}
    return not detector.findings_for(data, detector.context_for(data, origin))


def own_creations():
    for request in requests:
        if request[0] == "graphql":
            body = request[1]
            if body.get("repositoryId") == repository_id(*OWN.split("/")):
                labels = [i.removeprefix("L:") for i in body.get("labelIds") or []]
                yield labels, body.get("body") or ""
            continue
        _, path, raw = request
        if path.lower() == f"/api/v3/repos/{OWN}/issues":
            sent = json.loads(raw) if raw.strip() else {}
            yield list(sent.get("labels") or []), str(sent.get("body") or "")


def unmet(labels, body):
    kinds = {label for label in labels if label.startswith(FLOW) and label != FLOW}
    if len(kinds) == 1:
        return None
    if len(kinds) > 1:
        return f"flow:* が {len(kinds)} つ"
    return None if detector.has_declaration_line(body) else "flow:* も宣言の行も無い"


def replay(command):
    requests.clear()
    # 終わらない本文(`--body-file /dev/zero`)は gh が読み終えず、作成を送らないまま止まる。
    try:
        subprocess.run(["bash", "-c", command], cwd=work, env=gh_env, stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    except subprocess.TimeoutExpired:
        pass
    reasons = [reason for labels, body in own_creations() if (reason := unmet(labels, body))]
    return reasons[0] if reasons else None


def variants(text):
    first, _, rest = text.partition("⏎")
    simple = not any(mark in first for mark in ("$(", "`", "&&", "||", ";", "¦"))
    kind = "issue" if first.startswith("gh issue create") else "api" if first.startswith("gh api ") else None
    yield "", text
    if not (simple and kind):
        return
    for suffix in VARIANTS[kind]:
        yield suffix, first + suffix + ("⏎" + rest if rest else "")


for line in sys.stdin:
    label, text = line.rstrip("\n").split("|", 1)
    for suffix, variant in variants(text):
        name = label + (f" ＋{suffix.strip()}" if suffix else "")
        command = expand(variant)
        try:
            passed = detector_passes(command)
            reason = replay(command) if passed else None
        except Exception:
            traceback.print_exc()
            print(f"NG|{name}|判定か実行が例外で落ちた")
            continue
        print(f"NG|{name}|検出器は通したが、実物は{reason}作成を送った" if reason else f"ok|{name}|-")
PY
)"

# 検出器の表の `bash` 形で `miss` 以外の行を `ケース名|入力` で出す。
replayed_rows() {
  awk '/^cases="\$\(cat <<'"'"'CASES'"'"'$/ { inside = 1; next } inside && /^CASES$/ { exit } inside' \
    "$lib_dir/issue-flow-kind-cases.sh" |
    awk -F '|' '$1 != "miss" && ($3 == "bash" || $3 == "bash-nocwd") { label = $4; sub(/^[^|]*\|[^|]*\|[^|]*\|[^|]*\|/, ""); print label "|" $0 }'
}

missing_tools=""
for tool in gh openssl python3; do
  command -v "$tool" >/dev/null 2>&1 || missing_tools="$missing_tools $tool"
done
if [ -n "$missing_tools" ]; then
  printf 'NG   実物で確かめるコマンドが無い:%s\n' "$missing_tools"
  exit 1
fi

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost -addext "subjectAltName=DNS:localhost" \
  -keyout "$server_dir/key.pem" -out "$server_dir/cert.pem" >/dev/null 2>&1
place_files

rows="$(replayed_rows)"
results="$(printf '%s\n' "$rows" | python3 -c "$replay_runner" "$detector" "$work" "$own_origin" "$server_dir")"

cases_before=$cases_reported
while IFS='|' read -r verdict label reason; do
  [ -n "$label" ] || continue
  if [ "$verdict" = "ok" ]; then
    report_case ok ok "$label"
  else
    report_case ok NG "$label（$reason）"
  fi
done <<<"$results"
report_cases_ran replayed_rows "$cases_before"

exit "$cases_failed"
