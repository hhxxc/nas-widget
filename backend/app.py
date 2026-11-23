"""NAS 待办 API：账号密码注册/登录（Bearer 会话），按用户隔离的待办（SQLite 存储）。

- 口令：PBKDF2-HMAC-SHA256（每用户独立盐），绝不存明文
- 会话：随机 token，服务端只存 SHA-256 摘要，30 天过期
- 待办：user_id 隔离；历史上无主（API Key 时代）的待办自动归属第一个注册的用户
"""
import hashlib
import hmac
import os
import re
import secrets
import sqlite3
import time
import uuid
from pathlib import Path

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

DATA_DIR = Path(os.environ.get("DATA_DIR", str(Path(__file__).resolve().parent.parent / "data")))
WEB_DIR = Path(os.environ.get("WEB_DIR", str(Path(__file__).resolve().parent.parent / "web")))
DB_PATH = DATA_DIR / "todos.db"
DATA_DIR.mkdir(parents=True, exist_ok=True)

MAX_USERS = int(os.environ.get("MAX_USERS", "5"))
TOKEN_TTL = 30 * 24 * 3600  # 30 天
PBKDF2_ITERS = 100_000
LOGIN_RATE = (5, 600)  # 10 分钟内最多 5 次失败

app = FastAPI(title="NAS Widget API", docs_url=None, redoc_url=None)

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    pass_hash TEXT NOT NULL,
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL,
    created_at REAL NOT NULL,
    expires_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS todos (
    id TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    done INTEGER NOT NULL DEFAULT 0,
    created_at REAL NOT NULL,
    user_id INTEGER
);
"""


def get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    # 迁移：API Key 时代的 todos 表没有 user_id 列
    cols = [r["name"] for r in conn.execute("PRAGMA table_info(todos)")]
    if "user_id" not in cols:
        conn.execute("ALTER TABLE todos ADD COLUMN user_id INTEGER")
        conn.commit()
    return conn


# ---------- 口令与令牌 ----------

def hash_password(pw: str) -> str:
    salt = secrets.token_bytes(16)
    h = hashlib.pbkdf2_hmac("sha256", pw.encode("utf-8"), salt, PBKDF2_ITERS)
    return "pbkdf2_sha256$%d$%s$%s" % (PBKDF2_ITERS, salt.hex(), h.hex())


def verify_password(pw: str, stored: str) -> bool:
    try:
        _, iters, salt_hex, hash_hex = stored.split("$")
        h = hashlib.pbkdf2_hmac("sha256", pw.encode("utf-8"), bytes.fromhex(salt_hex), int(iters))
        return hmac.compare_digest(h.hex(), hash_hex)
    except Exception:
        return False


def digest(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


# ---------- 认证 ----------

def issue_token(conn: sqlite3.Connection, user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    now = time.time()
    conn.execute(
        "INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)",
        (digest(token), user_id, now, now + TOKEN_TTL),
    )
    conn.execute("DELETE FROM sessions WHERE expires_at < ?", (now,))  # 顺手清理过期会话
    conn.commit()
    return token


def current_user(authorization: str = Header(default="")) -> sqlite3.Row:
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="not authenticated")
    token = authorization[7:].strip()
    conn = get_db()
    try:
        row = conn.execute(
            "SELECT u.id AS uid, u.username AS username FROM sessions s "
            "JOIN users u ON u.id = s.user_id "
            "WHERE s.token_hash = ? AND s.expires_at > ?",
            (digest(token), time.time()),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=401, detail="session expired, please login again")
        return row
    finally:
        conn.close()


# 失败登录限速（内存态，重启即清零）
_failed_logins: dict[str, list[float]] = {}


def _rate_ok(username: str) -> bool:
    now = time.time()
    hits = [t for t in _failed_logins.get(username, []) if now - t < LOGIN_RATE[1]]
    _failed_logins[username] = hits
    return len(hits) < LOGIN_RATE[0]


def _record_fail(username: str) -> None:
    _failed_logins.setdefault(username, []).append(time.time())


# ---------- 模型 ----------

class AuthIn(BaseModel):
    username: str = Field(min_length=2, max_length=24)
    password: str = Field(min_length=6, max_length=128)


class TodoIn(BaseModel):
    content: str = Field(min_length=1, max_length=200)


class TodoPatch(BaseModel):
    content: str | None = Field(default=None, min_length=1, max_length=200)
    done: bool | None = None


# ---------- 路由 ----------

@app.get("/api/health")
def health():
    return {"ok": True, "time": int(time.time())}


@app.post("/api/auth/register")
def register(auth: AuthIn):
    username = auth.username.strip()
    if not re.fullmatch(r"[\w\-.]{2,24}", username):
        raise HTTPException(status_code=400, detail="用户名限 2-24 位，字母/数字/中文/点/横线/下划线")
    conn = get_db()
    try:
        n = conn.execute("SELECT COUNT(*) AS c FROM users").fetchone()["c"]
        if n >= MAX_USERS:
            raise HTTPException(status_code=403, detail="注册已关闭（用户数已达上限）")
        if conn.execute("SELECT 1 FROM users WHERE username = ?", (username,)).fetchone():
            raise HTTPException(status_code=409, detail="用户名已存在")
        cur = conn.execute(
            "INSERT INTO users (username, pass_hash, created_at) VALUES (?, ?, ?)",
            (username, hash_password(auth.password), time.time()),
        )
        uid = cur.lastrowid
        # 首个注册用户收编 API Key 时代的无主待办
        claimed = conn.execute(
            "UPDATE todos SET user_id = ? WHERE user_id IS NULL", (uid,)
        ).rowcount
        conn.commit()
        token = issue_token(conn, uid)
        return {"token": token, "username": username, "claimed": claimed}
    finally:
        conn.close()


@app.post("/api/auth/login")
def login(auth: AuthIn):
    username = auth.username.strip()
    if not _rate_ok(username):
        raise HTTPException(status_code=429, detail="失败次数过多，请 10 分钟后再试")
    conn = get_db()
    try:
        row = conn.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
        if row is None or not verify_password(auth.password, row["pass_hash"]):
            _record_fail(username)
            raise HTTPException(status_code=401, detail="用户名或密码错误")
        _failed_logins.pop(username, None)
        token = issue_token(conn, row["id"])
        return {"token": token, "username": username}
    finally:
        conn.close()


@app.post("/api/auth/logout")
def logout(user: sqlite3.Row = Depends(current_user), authorization: str = Header(default="")):
    conn = get_db()
    try:
        conn.execute("DELETE FROM sessions WHERE token_hash = ?", (digest(authorization[7:].strip()),))
        conn.commit()
    finally:
        conn.close()
    return {"ok": True}


@app.get("/api/me")
def me(user: sqlite3.Row = Depends(current_user)):
    return {"username": user["username"]}


def row_to_dict(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "content": row["content"],
        "done": bool(row["done"]),
        "createdAt": row["created_at"],
    }


@app.get("/api/todos")
def list_todos(user: sqlite3.Row = Depends(current_user)):
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT * FROM todos WHERE user_id = ? ORDER BY done ASC, created_at DESC",
            (user["uid"],),
        ).fetchall()
        return {"items": [row_to_dict(r) for r in rows]}
    finally:
        conn.close()


@app.post("/api/todos")
def add_todo(todo: TodoIn, user: sqlite3.Row = Depends(current_user)):
    item_id = uuid.uuid4().hex[:12]
    conn = get_db()
    try:
        conn.execute(
            "INSERT INTO todos (id, content, done, created_at, user_id) VALUES (?, ?, 0, ?, ?)",
            (item_id, todo.content.strip(), time.time(), user["uid"]),
        )
        conn.commit()
        row = conn.execute("SELECT * FROM todos WHERE id = ?", (item_id,)).fetchone()
        return {"item": row_to_dict(row)}
    finally:
        conn.close()


@app.patch("/api/todos/{item_id}")
def patch_todo(item_id: str, patch: TodoPatch, user: sqlite3.Row = Depends(current_user)):
    conn = get_db()
    try:
        row = conn.execute(
            "SELECT * FROM todos WHERE id = ? AND user_id = ?", (item_id, user["uid"])
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="todo not found")
        content = patch.content.strip() if patch.content is not None else row["content"]
        done = int(patch.done) if patch.done is not None else row["done"]
        conn.execute(
            "UPDATE todos SET content = ?, done = ? WHERE id = ? AND user_id = ?",
            (content, done, item_id, user["uid"]),
        )
        conn.commit()
        row = conn.execute("SELECT * FROM todos WHERE id = ?", (item_id,)).fetchone()
        return {"item": row_to_dict(row)}
    finally:
        conn.close()


@app.delete("/api/todos/{item_id}")
def delete_todo(item_id: str, user: sqlite3.Row = Depends(current_user)):
    conn = get_db()
    try:
        cur = conn.execute(
            "DELETE FROM todos WHERE id = ? AND user_id = ?", (item_id, user["uid"])
        )
        conn.commit()
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="todo not found")
        return {"ok": True}
    finally:
        conn.close()


app.mount("/", StaticFiles(directory=str(WEB_DIR), html=True), name="web")
